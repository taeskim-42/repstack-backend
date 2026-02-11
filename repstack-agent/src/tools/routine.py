"""Routine management tools."""

from src.tools._base import rails_api_call

ROUTINE_TOOLS = [
    {
        "name": "generate_routine",
        "description": "Generate today's workout routine for the user. Call this when user asks for a routine, wants to start working out, or asks what exercises to do today.",
        "input_schema": {
            "type": "object",
            "properties": {
                "goal": {"type": "string", "description": "Optional workout goal"},
                "condition": {"type": "string", "description": "Optional condition notes"},
            },
            "required": [],
        },
    },
    {
        "name": "replace_exercise",
        "description": "Replace an exercise in the current routine with a different one.",
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {"type": "string", "description": "Name of exercise to replace"},
                "reason": {"type": "string", "description": "Why user wants to replace"},
            },
            "required": ["exercise_name"],
        },
    },
    {
        "name": "add_exercise",
        "description": "Add a new exercise to the current routine.",
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {"type": "string", "description": "Name of exercise to add"},
                "sets": {"type": "integer", "description": "Number of sets"},
                "reps": {"type": "integer", "description": "Number of reps"},
                "target_muscle": {"type": "string", "description": "Target muscle group"},
            },
            "required": ["exercise_name"],
        },
    },
    {
        "name": "delete_exercise",
        "description": "Remove an exercise from the current routine.",
        "input_schema": {
            "type": "object",
            "properties": {
                "exercise_name": {"type": "string", "description": "Name of exercise to delete"},
            },
            "required": ["exercise_name"],
        },
    },
]


async def handle_routine_tool(tool_name: str, tool_input: dict, user_id: int) -> dict:
    """Handle routine-related tool calls via Rails Internal API."""
    endpoints = {
        "generate_routine": "/routines/generate",
        "replace_exercise": "/routines/replace_exercise",
        "add_exercise": "/routines/add_exercise",
        "delete_exercise": "/routines/delete_exercise",
    }
    return await rails_api_call("POST", endpoints[tool_name], user_id, json=tool_input)
