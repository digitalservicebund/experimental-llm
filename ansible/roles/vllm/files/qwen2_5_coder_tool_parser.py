"""Tool call parser for Qwen2.5-Coder models using <tools> tag format.

Extracts JSON tool calls from <tools>...</tools> tags in model output.
Chat template injects few-shot <tools> examples to induce the format.
Use with --chat-template examples/tool_chat_template_qwen2_5_coder.jinja

Supported formats:
    <tools>{"name": "func", "arguments": {...}}</tools>
    <tools>{...}</tools><tools>{...}</tools>  (parallel)
    <tools>[{...}, {...}]</tools>             (array)
    <tools>{...}\n{...}</tools>               (JSONL)
    <tools>{...}                              (unclosed, streaming)
"""

import json
import os
import re
import traceback
from collections.abc import Sequence
from datetime import datetime, timezone
from typing import Any

try:
    # vLLM >= 0.29.x
    from vllm.entrypoints.generate.base.protocol import (
        DeltaFunctionCall,
        DeltaMessage,
        DeltaToolCall,
        ExtractedToolCallInformation,
        FunctionCall,
        ToolCall,
    )
    from vllm.entrypoints.openai.chat_completion.protocol import (
        ChatCompletionRequest,
    )
except ImportError:
    try:
        # vLLM >= 0.15.x and < 0.29.x (protocol split into submodules)
        from vllm.entrypoints.openai.chat_completion.protocol import (
            ChatCompletionRequest,
        )
        from vllm.entrypoints.openai.engine.protocol import (
            DeltaFunctionCall,
            DeltaMessage,
            DeltaToolCall,
            ExtractedToolCallInformation,
            FunctionCall,
            ToolCall,
        )
    except ImportError:
        # vLLM <= 0.14.x (single protocol module)
        from vllm.entrypoints.openai.protocol import (  # type: ignore[no-redef]
            ChatCompletionRequest,
            DeltaFunctionCall,
            DeltaMessage,
            DeltaToolCall,
            ExtractedToolCallInformation,
            FunctionCall,
            ToolCall,
        )
from vllm.logger import init_logger
from vllm.tool_parsers.abstract_tool_parser import (
    ToolParser,
    ToolParserManager,
)

try:
    # vLLM >= 0.15.x (AnyTokenizer renamed to TokenizerLike)
    from vllm.tokenizers import TokenizerLike as AnyTokenizer
except ImportError:
    # vLLM <= 0.14.x
    from vllm.transformers_utils.tokenizer import AnyTokenizer  # type: ignore[no-redef]

logger = init_logger(__name__)
MAX_DEBUG_LOG_CHARS = 4000
DEBUG_LOG_FILE_ENV_VAR = "QWEN25_CODER_DEBUG_FILE"
DEFAULT_DEBUG_LOG_FILE = "/tmp/qwen2_5_coder_tool_parser.log"


def _truncate_for_log(value: Any, limit: int = MAX_DEBUG_LOG_CHARS) -> str:
    text = value if isinstance(value, str) else repr(value)
    if len(text) <= limit:
        return text
    return f"{text[:limit]}...<truncated {len(text) - limit} chars>"


def _serialize_for_log(value: Any) -> str:
    if hasattr(value, "model_dump"):
        try:
            return json.dumps(value.model_dump(mode="json"), ensure_ascii=False)
        except TypeError:
            pass
    return _truncate_for_log(value)


def _write_debug_file(message: str) -> None:
    path = os.environ.get(DEBUG_LOG_FILE_ENV_VAR, DEFAULT_DEBUG_LOG_FILE)
    timestamp = datetime.now(timezone.utc).isoformat()
    try:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{timestamp} {message}\n")
    except Exception:
        logger.exception(
            "[qwen2_5_coder_debug] failed to write debug file %s",
            path,
        )


def _debug_log(message: str, *args: Any) -> None:
    if args:
        try:
            rendered = message % args
        except Exception:
            rendered = f"{message} | args={args!r}"
    else:
        rendered = message
    logger.info(rendered)
    _write_debug_file(rendered)


_write_debug_file(
    "[qwen2_5_coder_debug] plugin module imported and registration decorator about to run"
)


def _partial_tag_overlap(text: str, tag: str) -> int:
    """Return the longest prefix length of *tag* matching a suffix of *text*."""
    for k in range(min(len(tag) - 1, len(text)), 0, -1):
        if text.endswith(tag[:k]):
            return k
    return 0


@ToolParserManager.register_module(["qwen2_5_coder"])
class Qwen25CoderToolParser(ToolParser):
    """Parser for Qwen2.5-Coder <tools> tag format.

    Chat template injects few-shot <tools> examples into system prompt.
    Not applicable to Qwen2.5 (non-Coder) which uses hermes natively.
    """

    def __init__(self, tokenizer: AnyTokenizer, tools=None):
        if tools is not None:
            super().__init__(tokenizer, tools)
        else:
            super().__init__(tokenizer)

        _debug_log(
            "[qwen2_5_coder_debug] initialized parser with %s tools",
            len(self.tools),
        )

        # <tools> tag tokens
        self.tool_call_start_token: str = "<tools>"
        self.tool_call_end_token: str = "</tools>"

        # Streaming state
        self.current_tool_id: int = -1
        self._sent_content_idx: int = 0
        self._raw_tool_call_start_idx: int | None = None

        # Pattern: closed tag or unclosed tag (streaming edge case)
        self.tool_call_regex = re.compile(
            r"<tools>\s*(.*?)\s*</tools>|<tools>\s*(.*)",
            re.DOTALL
        )
        # Pattern: closed tags only (for streaming match counting)
        self.tool_call_closed_regex = re.compile(
            r"<tools>\s*(.*?)\s*</tools>",
            re.DOTALL
        )
        self.standalone_json_object_regex = re.compile(r"(?m)^[ \t]*\{")

    def extract_tool_calls(
        self,
        model_output: str,
        request: ChatCompletionRequest,
    ) -> ExtractedToolCallInformation:
        """
        Extract tool calls from model output (non-streaming).

        Args:
            model_output: Full model response text
            request: Original chat completion request

        Returns:
            ExtractedToolCallInformation with parsed tool calls
        """
        _debug_log(
            "[qwen2_5_coder_debug] extract_tool_calls input=%s",
            _truncate_for_log(model_output),
        )

        # No <tools> tag found — try fallback raw JSON tool-call parsing.
        if self.tool_call_start_token not in model_output:
            fallback_result = self._extract_tool_calls_without_tags(model_output)
            if fallback_result is not None:
                _debug_log(
                    "[qwen2_5_coder_debug] extract_tool_calls raw-json fallback output=%s",
                    _serialize_for_log(fallback_result),
                )
                return fallback_result
            _debug_log(
                "[qwen2_5_coder_debug] no <tools> tag found; returning content-only output=%s",
                _truncate_for_log(model_output),
            )
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

        try:
            tool_calls: list[ToolCall] = []
            text_parts: list[str] = []
            last_end = 0

            for match in self.tool_call_regex.finditer(model_output):
                if match.start() > last_end:
                    text_parts.append(model_output[last_end:match.start()])

                # Parse JSON (group(1)=closed tag, group(2)=unclosed tag)
                json_str = (match.group(1) or match.group(2) or "").strip()
                _debug_log(
                    "[qwen2_5_coder_debug] found tool fragment=%s",
                    _truncate_for_log(json_str),
                )
                parsed = self._parse_tool_json(json_str)
                _debug_log(
                    "[qwen2_5_coder_debug] parsed fragment result=%s",
                    _truncate_for_log(parsed),
                )

                if parsed:
                    for tool_data in parsed:
                        tool_calls.append(
                            ToolCall(
                                id=f"tool_{len(tool_calls)}",
                                type="function",
                                function=FunctionCall(
                                    name=tool_data["name"],
                                    arguments=json.dumps(
                                        tool_data.get("arguments", {}),
                                        ensure_ascii=False
                                    ),
                                ),
                            )
                        )

                last_end = match.end()

            if last_end < len(model_output):
                text_parts.append(model_output[last_end:])

            content = "".join(text_parts).strip() or None

            result = ExtractedToolCallInformation(
                tools_called=len(tool_calls) > 0,
                tool_calls=tool_calls if tool_calls else [],
                content=content,
            )
            _debug_log(
                "[qwen2_5_coder_debug] extract_tool_calls output=%s",
                _serialize_for_log(result),
            )

            return result

        except Exception:
            logger.exception("Error in extracting tool call from response.")
            _write_debug_file(
                "[qwen2_5_coder_debug] extract_tool_calls exception\n"
                + traceback.format_exc()
            )
            return ExtractedToolCallInformation(
                tools_called=False,
                tool_calls=[],
                content=model_output,
            )

    def _extract_content(self, current_text: str) -> str | None:
        """Return unsent non-tool-call content, holding back any suffix
        that could be a partial ``<tools>`` prefix."""
        start = self.tool_call_start_token
        end = self.tool_call_end_token

        if start not in current_text:
            overlap = _partial_tag_overlap(current_text, start)
            sendable_idx = len(current_text) - overlap
        elif current_text.count(start) > current_text.count(end):
            sendable_idx = current_text.index(start)
        else:
            # All tags closed — skip past last </tools>, hold back
            # any partial <tools> prefix at the tail.
            after_pos = current_text.rfind(end) + len(end)
            if self._sent_content_idx < after_pos:
                self._sent_content_idx = after_pos
            overlap = _partial_tag_overlap(
                current_text[after_pos:], start
            )
            sendable_idx = len(current_text) - overlap

        if sendable_idx > self._sent_content_idx:
            content = current_text[self._sent_content_idx:sendable_idx]
            self._sent_content_idx = sendable_idx
            return content
        return None

    def _extract_content_until(self, current_text: str, end_idx: int) -> str | None:
        """Return unsent content up to end_idx and mark it as streamed."""
        if end_idx > self._sent_content_idx:
            content = current_text[self._sent_content_idx:end_idx]
            self._sent_content_idx = end_idx
            return content
        return None

    def _build_tool_calls(self, parsed: list[dict[str, Any]]) -> list[ToolCall]:
        tool_calls: list[ToolCall] = []
        for tool_data in parsed:
            tool_calls.append(
                ToolCall(
                    id=f"tool_{len(tool_calls)}",
                    type="function",
                    function=FunctionCall(
                        name=tool_data["name"],
                        arguments=json.dumps(
                            tool_data.get("arguments", {}),
                            ensure_ascii=False,
                        ),
                    ),
                )
            )
        return tool_calls

    def _build_delta_tool_calls(
        self,
        parsed: list[dict[str, Any]],
    ) -> list[DeltaToolCall]:
        delta_tool_calls: list[DeltaToolCall] = []
        for tool_data in parsed:
            self.current_tool_id += 1
            delta_tool_calls.append(
                DeltaToolCall(
                    index=self.current_tool_id,
                    id=f"tool_{self.current_tool_id}",
                    type="function",
                    function=DeltaFunctionCall(
                        name=tool_data["name"],
                        arguments=json.dumps(
                            tool_data.get("arguments", {}),
                            ensure_ascii=False,
                        ),
                    ),
                )
            )
        return delta_tool_calls

    def _find_standalone_json_object_starts(self, text: str) -> list[int]:
        return [match.end() - 1 for match in self.standalone_json_object_regex.finditer(text)]

    def _normalize_json_candidate(self, json_str: str) -> str:
        trimmed = json_str.strip()
        if trimmed.startswith("```"):
            lines = trimmed.splitlines()
            if lines:
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            trimmed = "\n".join(lines).strip()
        return trimmed

    def _extract_tool_calls_without_tags(
        self,
        model_output: str,
    ) -> ExtractedToolCallInformation | None:
        for start_idx in reversed(self._find_standalone_json_object_starts(model_output)):
            prefix = model_output[:start_idx]
            json_candidate = self._normalize_json_candidate(model_output[start_idx:])
            parsed = self._parse_tool_json(json_candidate, log_failures=False)
            if not parsed:
                continue

            result = ExtractedToolCallInformation(
                tools_called=True,
                tool_calls=self._build_tool_calls(parsed),
                content=prefix.strip() or None,
            )
            _debug_log(
                "[qwen2_5_coder_debug] raw-json fallback matched start=%s prefix=%s candidate=%s",
                start_idx,
                _truncate_for_log(prefix),
                _truncate_for_log(json_candidate),
            )
            return result

        return None

    def _extract_raw_json_tool_calls_streaming(
        self,
        previous_text: str,
        current_text: str,
    ) -> DeltaMessage | None:
        current_starts = self._find_standalone_json_object_starts(current_text)
        if not current_starts:
            self._raw_tool_call_start_idx = None
            return None

        start_idx = current_starts[-1]
        self._raw_tool_call_start_idx = start_idx
        prefix_content = self._extract_content_until(current_text, start_idx)
        current_candidate = self._normalize_json_candidate(current_text[start_idx:])
        prev_starts = self._find_standalone_json_object_starts(previous_text)
        prev_candidate = ""
        prev_parsed: list[dict[str, Any]] = []
        if prev_starts and prev_starts[-1] == start_idx:
            prev_candidate = self._normalize_json_candidate(previous_text[start_idx:])
            prev_parsed = self._parse_tool_json(prev_candidate, log_failures=False)

        parsed = self._parse_tool_json(current_candidate, log_failures=False)
        _debug_log(
            "[qwen2_5_coder_debug] streaming raw-json candidate start=%s prefix=%s current_candidate=%s prev_candidate=%s parsed=%s prev_parsed=%s",
            start_idx,
            _truncate_for_log(current_text[:start_idx]),
            _truncate_for_log(current_candidate),
            _truncate_for_log(prev_candidate),
            _truncate_for_log(parsed),
            _truncate_for_log(prev_parsed),
        )

        if not parsed:
            if prefix_content:
                result = DeltaMessage(content=prefix_content)
                _debug_log(
                    "[qwen2_5_coder_debug] streaming raw-json buffering candidate; emitted prefix=%s",
                    _serialize_for_log(result),
                )
                return result
            return None

        if len(prev_parsed) > len(parsed):
            prev_parsed = []

        new_parsed = parsed[len(prev_parsed):]
        delta_tool_calls = self._build_delta_tool_calls(new_parsed) if new_parsed else None
        self._sent_content_idx = len(current_text)
        if prefix_content or delta_tool_calls:
            result = DeltaMessage(content=prefix_content, tool_calls=delta_tool_calls)
            _debug_log(
                "[qwen2_5_coder_debug] streaming raw-json output=%s",
                _serialize_for_log(result),
            )
            return result

        return None

    def extract_tool_calls_streaming(
        self,
        previous_text: str,
        current_text: str,
        delta_text: str,
        previous_token_ids: Sequence[int],
        current_token_ids: Sequence[int],
        delta_token_ids: Sequence[int],
        request: ChatCompletionRequest,
    ) -> DeltaMessage | None:
        """Extract tool calls in streaming mode.

        Args:
            previous_text: Accumulated text up to the previous token
            current_text: Accumulated text up to the current token
            delta_text: Newly added text
            previous_token_ids: Previous token IDs
            current_token_ids: Current token IDs
            delta_token_ids: New token IDs
            request: Original chat completion request

        Returns:
            DeltaMessage or None
        """
        _debug_log(
            "[qwen2_5_coder_debug] extract_tool_calls_streaming delta=%s current=%s",
            _truncate_for_log(delta_text),
            _truncate_for_log(current_text),
        )

        if self.tool_call_start_token not in current_text:
            raw_json_result = self._extract_raw_json_tool_calls_streaming(
                previous_text,
                current_text,
            )
            if raw_json_result is not None:
                return raw_json_result

            content = self._extract_content(current_text)
            if content:
                result = DeltaMessage(content=content)
                _debug_log(
                    "[qwen2_5_coder_debug] streaming output(no tag)=%s",
                    _serialize_for_log(result),
                )
                return result
            return None

        content = self._extract_content(current_text)

        try:
            current_matches = list(
                self.tool_call_closed_regex.finditer(current_text)
            )
            prev_matches = list(
                self.tool_call_closed_regex.finditer(previous_text)
            )

            # Detect newly completed <tools>...</tools> pairs
            delta_tool_calls = None
            if len(current_matches) > len(prev_matches):
                delta_tool_calls = []
                for new_match in current_matches[len(prev_matches):]:
                    json_str = new_match.group(1).strip()
                    _debug_log(
                        "[qwen2_5_coder_debug] streaming completed tool fragment=%s",
                        _truncate_for_log(json_str),
                    )
                    parsed = self._parse_tool_json(json_str)
                    _debug_log(
                        "[qwen2_5_coder_debug] streaming parsed fragment result=%s",
                        _truncate_for_log(parsed),
                    )

                    if parsed:
                        delta_tool_calls.extend(
                            self._build_delta_tool_calls(parsed)
                        )
                if delta_tool_calls:
                    end_of_last_tag = current_matches[-1].end()
                    if end_of_last_tag > self._sent_content_idx:
                        self._sent_content_idx = end_of_last_tag
                else:
                    delta_tool_calls = None

            # Inside an unclosed <tools> tag — buffer until closed
            if current_text.count(self.tool_call_start_token) > \
               current_text.count(self.tool_call_end_token):
                if content or delta_tool_calls:
                    result = DeltaMessage(
                        content=content, tool_calls=delta_tool_calls
                    )
                    _debug_log(
                        "[qwen2_5_coder_debug] streaming output(open tag)=%s",
                        _serialize_for_log(result),
                    )
                    return result
                return None

            # All tags closed — pick up trailing text after </tools>
            trailing = self._extract_content(current_text)
            parts = [p for p in (content, trailing) if p]
            combined = "".join(parts) or None

            if combined or delta_tool_calls:
                result = DeltaMessage(
                    content=combined, tool_calls=delta_tool_calls
                )
                _debug_log(
                    "[qwen2_5_coder_debug] streaming output=%s",
                    _serialize_for_log(result),
                )
                return result
            return None

        except Exception:
            logger.exception("Error in streaming tool call extraction.")
            _write_debug_file(
                "[qwen2_5_coder_debug] extract_tool_calls_streaming exception\n"
                + traceback.format_exc()
            )
            return DeltaMessage(content=delta_text)

    def _parse_tool_json(
        self,
        json_str: str,
        *,
        log_failures: bool = True,
    ) -> list[dict[str, Any]]:
        """
        Parse a JSON string into a list of tool call dicts.

        Supported formats:
            1. Single object: {"name": "...", "arguments": {...}}
            2. Array: [{"name": "..."}, {"name": "..."}]
            3. JSONL (newline-separated): {"name": "..."}\n{"name": "..."}

        Args:
            json_str: JSON string extracted from <tools> tags

        Returns:
            List of tool call dicts [{"name": "...", "arguments": {...}}, ...]
        """
        json_str = self._normalize_json_candidate(json_str)
        result = self._try_parse_json(json_str)
        if result:
            _debug_log(
                "[qwen2_5_coder_debug] parsed tool JSON directly=%s",
                _truncate_for_log(result),
            )
            return result

        # Retry after normalizing double-escaped quotes (\\" -> \")
        # Some models (e.g. 14B) double-escape quotes in JSON output
        if '\\\\' in json_str or '\\"' in json_str:
            # \\" -> \"
            normalized = json_str.replace('\\\\"', '\\"')
            result = self._try_parse_json(normalized)
            if result:
                _debug_log(
                    "[qwen2_5_coder_debug] parsed normalized tool JSON=%s",
                    _truncate_for_log(result),
                )
                return result

        if log_failures:
            logger.warning("Failed to parse tool JSON: %s...", json_str[:100])
            _write_debug_file(
                "[qwen2_5_coder_debug] failed to parse tool JSON="
                + _truncate_for_log(json_str)
            )
        return []

    def _try_parse_json(self, json_str: str) -> list[dict[str, Any]]:
        """Try parsing JSON in multiple formats."""
        # 1. Try as single JSON (object or array)
        try:
            parsed = json.loads(json_str)

            # Array
            if isinstance(parsed, list):
                result = []
                for item in parsed:
                    if self._is_valid_tool_call(item):
                        result.append(item)
                return result

            # Single object
            if self._is_valid_tool_call(parsed):
                return [parsed]

            return []

        except json.JSONDecodeError:
            pass

        # 2. Try as JSONL (newline-separated JSON objects)
        result = []
        for line in json_str.strip().split('\n'):
            line = line.strip()
            if not line:
                continue
            line = line.rstrip(',')
            if not line:
                continue
            try:
                parsed = json.loads(line)
                if self._is_valid_tool_call(parsed):
                    result.append(parsed)
            except json.JSONDecodeError:
                continue

        if result:
            return result

        # 3. Try as comma-separated objects (wrap in array)
        # e.g., "{...}, {...}" -> "[{...}, {...}]"
        wrapped = f"[{json_str.strip()}]"
        try:
            parsed = json.loads(wrapped)
            if isinstance(parsed, list):
                for item in parsed:
                    if self._is_valid_tool_call(item):
                        result.append(item)
                if result:
                    return result
        except json.JSONDecodeError:
            pass

        return []

    def _is_valid_tool_call(self, obj: Any) -> bool:
        """Check if obj is a valid tool call dict (has 'name' string)."""
        if not isinstance(obj, dict):
            return False
        if "name" not in obj:
            return False
        return isinstance(obj["name"], str)


_write_debug_file(
    "[qwen2_5_coder_debug] plugin module fully loaded; Qwen25CoderToolParser class definition complete"
)

