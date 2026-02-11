"""DB-backed session management via Rails Internal API."""

import logging

from src.tools._base import rails_api_call

logger = logging.getLogger(__name__)


class SessionManager:
    """Manages conversation history persistence through Rails Internal API."""

    async def load_history(self, user_id: int) -> list[dict]:
        """Load conversation history from Rails DB."""
        try:
            resp = await rails_api_call("GET", f"/sessions/{user_id}/messages", user_id)
            if not resp.get("success"):
                return []

            messages = resp.get("messages", [])
            history = []
            for msg in messages:
                content = msg["content"]
                role = msg["role"]

                # Summary messages stored as {"type": "summary", "text": "..."}
                if isinstance(content, dict) and content.get("type") == "summary":
                    content = content["text"]

                # Anthropic API only accepts "user" and "assistant" roles.
                # tool_result messages are sent as role="user" with tool_result content blocks.
                if role == "tool_result":
                    role = "user"

                # Skip messages with empty content
                if not content:
                    continue
                if isinstance(content, str) and not content.strip():
                    continue
                if isinstance(content, list) and len(content) == 0:
                    continue

                history.append({"role": role, "content": content})
            return history
        except Exception as e:
            logger.warning(f"Failed to load history for user {user_id}: {e}")
            return []

    async def save_messages(self, user_id: int, messages: list[dict]) -> bool:
        """Save new messages to Rails DB."""
        if not messages:
            return True

        try:
            payload = []
            for msg in messages:
                content = msg["content"]
                # Convert anthropic content blocks to serializable format
                if hasattr(content, "__iter__") and not isinstance(content, (str, dict)):
                    content = _serialize_content(content)

                payload.append({
                    "role": msg["role"],
                    "content": content,
                    "token_count": msg.get("token_count", 0),
                })

            resp = await rails_api_call(
                "POST",
                f"/sessions/{user_id}/messages",
                user_id,
                json={"messages": payload},
            )
            return resp.get("success", False)
        except Exception as e:
            logger.error(f"Failed to save messages for user {user_id}: {e}")
            return False

    async def get_total_tokens(self, user_id: int) -> int:
        """Get total token count for the active session."""
        try:
            resp = await rails_api_call("GET", f"/sessions/{user_id}/messages", user_id)
            return resp.get("total_tokens", 0)
        except Exception:
            return 0

    async def replace_history(self, user_id: int, messages: list[dict]) -> bool:
        """Replace all messages with a compacted set (used after summarization)."""
        try:
            payload = []
            for msg in messages:
                content = msg["content"]
                if hasattr(content, "__iter__") and not isinstance(content, (str, dict)):
                    content = _serialize_content(content)
                payload.append({
                    "role": msg["role"],
                    "content": content,
                    "token_count": msg.get("token_count", 0),
                })

            resp = await rails_api_call(
                "POST",
                f"/sessions/{user_id}/summarize",
                user_id,
                json={"messages": payload},
            )
            return resp.get("success", False)
        except Exception as e:
            logger.error(f"Failed to replace history for user {user_id}: {e}")
            return False


def _serialize_content(content) -> list | str:
    """Convert anthropic SDK content blocks to JSON-serializable format."""
    if isinstance(content, str):
        return content

    serialized = []
    for block in content:
        if hasattr(block, "model_dump"):
            serialized.append(block.model_dump())
        elif isinstance(block, dict):
            serialized.append(block)
        elif hasattr(block, "text"):
            serialized.append({"type": "text", "text": block.text})
        elif hasattr(block, "name"):
            serialized.append({
                "type": "tool_use",
                "id": getattr(block, "id", ""),
                "name": block.name,
                "input": getattr(block, "input", {}),
            })
        else:
            serialized.append(str(block))
    return serialized
