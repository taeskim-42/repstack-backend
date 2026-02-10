"""FastAPI server for RepStack Agent Service."""

import logging

from fastapi import Depends, FastAPI, HTTPException, Request
from pydantic import BaseModel

from src.agent import TrainerAgent
from src.config import settings
from src.tools._base import rails_api_call

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="RepStack Agent Service", version="0.1.0")
agent = TrainerAgent()


# --- Auth ---

async def verify_token(request: Request):
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer ") or auth[7:] != settings.agent_api_token:
        raise HTTPException(status_code=401, detail="Unauthorized")


# --- Models ---

class ChatRequest(BaseModel):
    user_id: int
    message: str
    routine_id: int | None = None
    session_id: str | None = None


class ChatResponse(BaseModel):
    success: bool
    message: str | None = None
    error: str | None = None
    tool_calls: list[dict] | None = None
    usage: dict | None = None


# --- Endpoints ---

@app.post("/chat", response_model=ChatResponse, dependencies=[Depends(verify_token)])
async def chat(req: ChatRequest):
    """Main chat endpoint — process user message through AI agent."""
    try:
        # Fetch user context from Rails
        user_context = await _fetch_user_context(req.user_id)
    except Exception as e:
        logger.warning(f"Failed to fetch user context: {e}")
        user_context = {}

    result = await agent.chat(req.user_id, req.message, user_context)
    return ChatResponse(**result)


@app.post("/sessions/{user_id}/reset", dependencies=[Depends(verify_token)])
async def reset_session(user_id: int):
    """Reset conversation session for a user."""
    agent.reset_session(user_id)
    return {"success": True, "message": "Session reset"}


@app.get("/sessions/{user_id}/status", dependencies=[Depends(verify_token)])
async def session_status(user_id: int):
    """Get session status for a user."""
    return agent.session_info(user_id)


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "service": "repstack-agent"}


# --- Helpers ---

async def _fetch_user_context(user_id: int) -> dict:
    """Fetch profile + memory from Rails Internal API."""
    context = {}
    try:
        profile = await rails_api_call("GET", f"/users/{user_id}/profile", user_id)
        context["profile"] = profile.get("data", {})
    except Exception:
        pass
    try:
        memory = await rails_api_call("GET", f"/users/{user_id}/memory", user_id)
        context["memory"] = memory.get("data", {})
    except Exception:
        pass
    return context
