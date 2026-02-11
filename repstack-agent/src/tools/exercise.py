"""Exercise recording tool."""

from src.tools._base import rails_api_call

EXERCISE_TOOLS = [
    {
        "name": "record_exercise",
        "description": "Record an exercise set. Use when the user tells you what exercise they did with weight and reps.",
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {"type": "string", "description": "Name of exercise"},
                "weight_kg": {"type": "number", "description": "Weight in kg"},
                "reps": {"type": "integer", "description": "Number of reps"},
                "set_number": {"type": "integer", "description": "Set number"},
            },
            "required": ["exercise_name", "reps"],
        },
    },
]


async def handle_exercise_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    return await rails_api_call("POST", "/exercises/record", user_id, json=tool_input)
