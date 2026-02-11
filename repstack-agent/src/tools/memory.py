"""User memory read/write tools."""

from src.tools._base import rails_api_call

MEMORY_TOOLS = [
    {
        "name": "read_memory",
        "description": "Read stored long-term memory about the user (key facts, personality, milestones). Use at session start to recall user context.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "write_memory",
        "description": "Store a new observation or fact about the user for long-term memory. Use when you learn something important about the user.",
        "input_schema": {
            "type": "object",
            "properties": {
                "type": {
                    "type": "string",
                    "enum": ["fact", "personality_profile", "milestone"],
                    "description": "Type of memory to store",
                },
                "category": {
                    "type": "string",
                    "description": "Category for facts (e.g., injury, goal, preference, habit)",
                },
                "content": {"type": "string", "description": "The content to remember"},
            },
            "required": ["type", "content"],
        },
    },
]


async def handle_memory_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    if tool_name == "read_memory":
        return await rails_api_call("GET", f"/users/{user_id}/memory", user_id)
    else:
        return await rails_api_call("POST", f"/users/{user_id}/memory", user_id, json=tool_input)
