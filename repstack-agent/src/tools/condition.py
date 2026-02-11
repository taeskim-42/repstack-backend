"""Condition check tool."""

from src.tools._base import rails_api_call

CONDITION_TOOLS = [
    {
        "name": "check_condition",
        "description": "Analyze and record the user's daily condition. Use when user describes how they feel today.",
        "input_schema": {
            "type": "object",
            "properties": {
                "condition_text": {"type": "string", "description": "User's condition description"},
            },
            "required": ["condition_text"],
        },
    },
]


async def handle_condition_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    return await rails_api_call("POST", "/conditions/check", user_id, json=tool_input)
