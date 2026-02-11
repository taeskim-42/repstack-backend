"""User profile and history tools."""

from src.tools._base import rails_api_call

PROFILE_TOOLS = [
    {
        "name": "get_user_profile",
        "description": "Get user's profile including level, goals, injuries, and fitness info. Use to personalize advice.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_training_history",
        "description": "Get user's recent training history summary. Use to understand their recent activity and progress.",
        "input_schema": {
            "type": "object",
            "properties": {
                "days": {"type": "integer", "description": "Number of days to look back (default 7)"},
            },
            "required": [],
        },
    },
    {
        "name": "get_today_routine",
        "description": "Check if user already has a routine for today.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
]


async def handle_profile_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    endpoints = {
        "get_user_profile": f"/users/{user_id}/profile",
        "get_training_history": f"/users/{user_id}/history",
        "get_today_routine": f"/users/{user_id}/today_routine",
    }
    params = {}
    if tool_name == "get_training_history" and "days" in tool_input:
        params["days"] = tool_input["days"]
    return await rails_api_call("GET", endpoints[tool_name], user_id, params=params)
