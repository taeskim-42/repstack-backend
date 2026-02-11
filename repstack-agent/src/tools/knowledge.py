"""Fitness knowledge search tools (RAG)."""

from src.tools._base import rails_api_call

KNOWLEDGE_TOOLS = [
    {
        "name": "search_fitness_knowledge",
        "description": (
            "Search the fitness knowledge base (curated from expert YouTube channels). "
            "Use for exercise technique, form checks, routine design, nutrition/recovery questions."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search query in Korean",
                },
                "knowledge_types": {
                    "type": "string",
                    "description": "Comma-separated types: exercise_technique, form_check, routine_design, nutrition_recovery",
                },
                "muscle_group": {
                    "type": "string",
                    "description": "Target muscle group filter",
                },
                "limit": {
                    "type": "integer",
                    "description": "Max results (default 5)",
                },
            },
            "required": ["query"],
        },
    },
]


async def handle_knowledge_tool(tool_name: str, tool_input: dict, user_id: int) -> str:
    params = {"query": tool_input["query"]}
    if tool_input.get("knowledge_types"):
        params["knowledge_types"] = tool_input["knowledge_types"]
    if tool_input.get("muscle_group"):
        params["muscle_group"] = tool_input["muscle_group"]
    if tool_input.get("limit"):
        params["limit"] = tool_input["limit"]

    result = await rails_api_call("GET", "/knowledge/search", user_id, params=params)
    return result.get("context_prompt") or str(result)
