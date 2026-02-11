"""Training plan explanation tool."""

from src.tools._base import rails_api_call

PLAN_TOOLS = [
    {
        "name": "explain_plan",
        "description": "Explain the user's long-term training program. Use when user asks about their program structure, phases, or progress.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]


async def handle_plan_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    return await rails_api_call("GET", "/programs/explain", user_id)
