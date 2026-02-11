"""MCP Tool definitions for Claude Agent."""

from src.tools.routine import ROUTINE_TOOLS, handle_routine_tool
from src.tools.exercise import EXERCISE_TOOLS, handle_exercise_tool
from src.tools.condition import CONDITION_TOOLS, handle_condition_tool
from src.tools.workout import WORKOUT_TOOLS, handle_workout_tool
from src.tools.feedback import FEEDBACK_TOOLS, handle_feedback_tool
from src.tools.plan import PLAN_TOOLS, handle_plan_tool
from src.tools.profile import PROFILE_TOOLS, handle_profile_tool
from src.tools.memory import MEMORY_TOOLS, handle_memory_tool
from src.tools.knowledge import KNOWLEDGE_TOOLS, handle_knowledge_tool

ALL_TOOLS = (
    ROUTINE_TOOLS
    + EXERCISE_TOOLS
    + CONDITION_TOOLS
    + WORKOUT_TOOLS
    + FEEDBACK_TOOLS
    + PLAN_TOOLS
    + PROFILE_TOOLS
    + MEMORY_TOOLS
    + KNOWLEDGE_TOOLS
)

TOOL_HANDLERS = {
    "generate_routine": handle_routine_tool,
    "replace_exercise": handle_routine_tool,
    "add_exercise": handle_routine_tool,
    "delete_exercise": handle_routine_tool,
    "record_exercise": handle_exercise_tool,
    "check_condition": handle_condition_tool,
    "complete_workout": handle_workout_tool,
    "submit_feedback": handle_feedback_tool,
    "explain_plan": handle_plan_tool,
    "get_user_profile": handle_profile_tool,
    "get_training_history": handle_profile_tool,
    "get_today_routine": handle_profile_tool,
    "read_memory": handle_memory_tool,
    "write_memory": handle_memory_tool,
    "search_fitness_knowledge": handle_knowledge_tool,
}
