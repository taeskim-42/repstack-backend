"""Shared HTTP client for Rails Internal API calls."""

import httpx

from src.config import settings


async def rails_api_call(method: str, path: str, user_id: int, **kwargs) -> dict:
    """Make an authenticated call to Rails Internal API."""
    url = f"{settings.rails_internal_api_url}{path}"
    headers = {
        "Authorization": f"Bearer {settings.rails_api_token}",
        "Content-Type": "application/json",
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        if method == "GET":
            params = kwargs.get("params", {})
            params["user_id"] = user_id
            response = await client.get(url, headers=headers, params=params)
        else:
            json_data = kwargs.get("json", {})
            json_data["user_id"] = user_id
            response = await client.post(url, headers=headers, json=json_data)

    response.raise_for_status()
    return response.json()
