"""Feedback submission tool."""

from src.tools._base import rails_api_call

FEEDBACK_TOOLS = [
    {
        "name": "submit_feedback",
        "description": "Submit workout feedback from the user. Use when user shares how the workout felt (too hard, too easy, just right, etc.).",
        "input_schema": {
            "type": "object",
            "properties": {
                "feedback_text": {"type": "string", "description": "User's feedback about the workout"},
                "rating": {"type": "integer", "description": "Rating 1-5 (1=too easy, 5=too hard)"},
            },
            "required": ["feedback_text"],
        },
    },
]


async def handle_feedback_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    return await rails_api_call("POST", "/feedbacks/submit", user_id, json=tool_input)
