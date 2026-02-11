"""Workout completion tool."""

from src.tools._base import rails_api_call

WORKOUT_TOOLS = [
    {
        "name": "complete_workout",
        "description": "Mark the current workout session as complete. Use when user says they're done working out.",
        "input_schema": {
            "type": "object",
            "properties": {
                "notes": {"type": "string", "description": "Optional completion notes"},
            },
            "required": [],
        },
    },
]


async def handle_workout_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    return await rails_api_call("POST", "/workouts/complete", user_id, json=tool_input)
