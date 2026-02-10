"""Claude Agent with tool use and conversation history management."""

import json
import logging

import anthropic

from src.config import settings
from src.session_manager import SessionManager, _serialize_content
from src.tools import ALL_TOOLS, TOOL_HANDLERS

logger = logging.getLogger(__name__)

# Tools that are "informational" and don't represent a primary action
_INFO_TOOLS = {"get_user_profile", "get_training_history", "get_today_routine", "read_memory", "write_memory"}


def build_system_prompt(user_context: dict) -> str:
    """Build personalized system prompt with user context."""
    profile = user_context.get("profile", {})
    memory = user_context.get("memory", {})
    key_facts = memory.get("key_facts", [])
    personality = memory.get("personality_profile")

    facts_text = ""
    if key_facts:
        facts_text = "\n".join(f"- [{f['category']}] {f['content']}" for f in key_facts[:30])

    personality_text = f"\n사용자 성격/대화 스타일: {personality}" if personality else ""

    return f"""당신은 RepStack의 전담 AI 피트니스 트레이너입니다.
이 사용자와 장기적인 1:1 트레이닝 관계를 유지합니다.

## 사용자 정보
- 이름: {profile.get('name', '사용자')}
- 레벨: {profile.get('current_level', 'beginner')} (수치: {profile.get('numeric_level', 1)})
- 목표: {profile.get('fitness_goal', '일반 체력')}
- 부상/주의: {profile.get('injuries', '없음')}
- 키/몸무게: {profile.get('height', '?')}cm / {profile.get('weight', '?')}kg
{personality_text}

## 기억하고 있는 사실들
{facts_text or '아직 기록된 사실이 없습니다.'}

## 행동 지침
1. 한국어로 대화합니다
2. 도구를 사용하여 루틴 생성, 운동 기록, 컨디션 체크, 피드백 수집 등을 수행합니다
3. 대화 중 중요한 정보를 발견하면 write_memory 도구로 기록합니다
4. 운동 관련 질문에 전문적이면서도 친근하게 답합니다
5. 사용자의 컨디션과 피드백을 반영하여 맞춤형 조언을 제공합니다
6. 응답은 간결하게, 핵심 위주로 합니다
7. 도구 사용 후 응답 끝에 사용자가 다음에 할 수 있는 행동 2-4개를 제안합니다.
   형식: suggestions: ["제안1", "제안2", "제안3"]
   예: suggestions: ["오늘 루틴 만들어줘", "컨디션 체크해줘", "운동 기록할게"]"""


class TrainerAgent:
    """AI Trainer Agent backed by Claude with tool use."""

    def __init__(self):
        self.client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        self.session_manager = SessionManager()
        # user_id -> conversation history (cache, restored from DB on first access)
        self._conversations: dict[int, list[dict]] = {}
        self._loaded_from_db: set[int] = set()

    async def _get_history(self, user_id: int) -> list[dict]:
        """Get conversation history, loading from DB if needed."""
        if user_id not in self._loaded_from_db:
            db_history = await self.session_manager.load_history(user_id)
            if db_history:
                self._conversations[user_id] = db_history
                logger.info(f"Loaded {len(db_history)} messages from DB for user {user_id}")
            else:
                self._conversations[user_id] = []
            self._loaded_from_db.add(user_id)

        if user_id not in self._conversations:
            self._conversations[user_id] = []
        return self._conversations[user_id]

    def _trim_history(self, user_id: int) -> None:
        """Trim conversation history to stay within token budget."""
        history = self._conversations.get(user_id, [])
        # Keep last 100 messages (rough limit)
        if len(history) > 100:
            self._conversations[user_id] = history[-80:]

    async def chat(self, user_id: int, message: str, user_context: dict | None = None) -> dict:
        """Process a user message and return agent response."""
        history = await self._get_history(user_id)
        system_prompt = build_system_prompt(user_context or {})

        # Track new messages for DB persistence
        new_messages: list[dict] = []

        # Add user message
        user_msg = {"role": "user", "content": message}
        history.append(user_msg)
        new_messages.append(user_msg)

        total_input_tokens = 0
        total_output_tokens = 0
        collected_tool_calls: list[dict] = []

        # Agentic loop: keep calling Claude until no more tool_use
        max_iterations = 10
        for _ in range(max_iterations):
            try:
                response = await self.client.messages.create(
                    model=settings.anthropic_model,
                    max_tokens=2048,
                    system=system_prompt,
                    tools=ALL_TOOLS,
                    messages=history,
                )
            except anthropic.APIError as e:
                logger.error(f"Anthropic API error: {e}")
                # Remove the user message we added
                history.pop()
                return {"success": False, "error": str(e)}

            total_input_tokens += response.usage.input_tokens
            total_output_tokens += response.usage.output_tokens

            # Serialize content blocks to dicts for consistent storage
            # (Anthropic API accepts both SDK objects and dict representations)
            serialized_content = _serialize_content(response.content)

            # Add assistant response to history (serialized for json compatibility)
            history.append({"role": "assistant", "content": serialized_content})
            new_messages.append({
                "role": "assistant",
                "content": serialized_content,
                "token_count": response.usage.output_tokens,
            })

            # Check if we need to handle tool calls
            if response.stop_reason != "tool_use":
                break

            # Process tool calls
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    try:
                        handler = TOOL_HANDLERS.get(block.name)
                        if handler:
                            result = await handler(block.name, block.input, user_id)
                        else:
                            result = f"Unknown tool: {block.name}"
                    except Exception as e:
                        logger.error(f"Tool error ({block.name}): {e}")
                        result = f"Tool error: {str(e)}"

                    # Collect tool call info for response
                    parsed_result = result if isinstance(result, dict) else _try_parse_json(result)
                    collected_tool_calls.append({
                        "name": block.name,
                        "input": block.input,
                        "result": parsed_result,
                    })

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": result if isinstance(result, str) else json.dumps(result),
                    })

            # Add tool results to history
            tool_result_msg = {"role": "user", "content": tool_results}
            history.append(tool_result_msg)
            new_messages.append({
                "role": "tool_result",
                "content": tool_results,
            })

        self._trim_history(user_id)

        # Persist new messages to DB
        try:
            await self.session_manager.save_messages(user_id, new_messages)
        except Exception as e:
            logger.error(f"Failed to persist messages for user {user_id}: {e}")

        # Check if compaction is needed
        try:
            await self._maybe_compact(user_id, system_prompt)
        except Exception as e:
            logger.error(f"Compaction failed for user {user_id}: {e}")

        # Extract text response
        text_parts = []
        for block in response.content:
            if hasattr(block, "text"):
                text_parts.append(block.text)

        return {
            "success": True,
            "message": "\n".join(text_parts),
            "tool_calls": collected_tool_calls,
            "usage": {
                "input_tokens": total_input_tokens,
                "output_tokens": total_output_tokens,
            },
        }

    def _estimate_tokens(self, user_id: int) -> int:
        """Estimate total tokens in conversation history.

        Korean text: ~2 chars/token, English: ~4 chars/token.
        Use conservative estimate of 2.5 chars/token.
        """
        history = self._conversations.get(user_id, [])
        total_chars = 0
        for msg in history:
            content = msg.get("content", "")
            if isinstance(content, str):
                total_chars += len(content)
            elif isinstance(content, list):
                total_chars += len(json.dumps(content, ensure_ascii=False))
            elif isinstance(content, dict):
                total_chars += len(json.dumps(content, ensure_ascii=False))
            else:
                total_chars += len(str(content))
        return int(total_chars / 2.5)

    async def _maybe_compact(self, user_id: int, system_prompt: str) -> None:
        """Compact conversation history if token budget exceeded."""
        estimated = self._estimate_tokens(user_id)
        threshold = settings.max_conversation_tokens  # default 150K

        if estimated < threshold * 0.8:  # 80% threshold = 120K
            return

        logger.info(f"Compacting conversation for user {user_id} (~{estimated} tokens)")
        history = self._conversations.get(user_id, [])
        if len(history) < 6:
            return

        # Split: summarize older half, keep recent half
        split_point = len(history) // 2
        old_messages = history[:split_point]
        recent_messages = history[split_point:]

        # Ask Claude to summarize the older conversation
        summary_prompt = (
            "다음 대화 이력을 간결하게 요약해주세요. "
            "중요한 정보(운동 기록, 루틴 변경, 피드백, 사용자 선호)를 포함하세요.\n\n"
        )
        for msg in old_messages:
            content = msg["content"]
            if isinstance(content, str):
                summary_prompt += f"[{msg['role']}]: {content[:500]}\n"
            elif isinstance(content, list):
                # Extract text from serialized content blocks
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        summary_prompt += f"[{msg['role']}]: {block['text'][:500]}\n"
                        break

        try:
            summary_response = await self.client.messages.create(
                model=settings.anthropic_model,
                max_tokens=1024,
                system="대화 이력을 요약하는 도우미입니다. 핵심 정보만 간결하게 요약하세요.",
                messages=[{"role": "user", "content": summary_prompt}],
            )
            summary_text = summary_response.content[0].text
            summary_tokens = int(len(summary_text) / 2.5)

            # Replace history: summary + recent messages
            # Anthropic requires first message to be "user" role
            compacted = [
                {"role": "user", "content": f"[시스템: 이전 대화 요약]\n{summary_text}"},
                {"role": "assistant", "content": "네, 이전 대화 내용을 기억하고 있습니다. 계속 도와드릴게요."},
                *recent_messages,
            ]
            self._conversations[user_id] = compacted

            # Replace DB history with compacted set
            await self.session_manager.replace_history(user_id, compacted)

            logger.info(
                f"Compacted user {user_id}: {len(old_messages)} old → summary, "
                f"kept {len(recent_messages)} recent"
            )
        except Exception as e:
            logger.error(f"Summary generation failed for user {user_id}: {e}")

    def reset_session(self, user_id: int) -> None:
        """Clear conversation history for a user."""
        self._conversations.pop(user_id, None)
        self._loaded_from_db.discard(user_id)

    def session_info(self, user_id: int) -> dict:
        """Get session info for a user (sync, uses cache only)."""
        history = self._conversations.get(user_id, [])
        return {
            "user_id": user_id,
            "message_count": len(history),
            "active": len(history) > 0,
        }


def _try_parse_json(value: str) -> dict | str:
    """Try to parse a string as JSON, return original on failure."""
    if not isinstance(value, str):
        return value
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return value
