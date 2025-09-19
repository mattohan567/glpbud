"""
Supabase database connection manager with singleton pattern and retry logic
"""
import os
import asyncio
import time
import random
from supabase import create_client, Client
from typing import Optional
import logging

logger = logging.getLogger(__name__)

def retry(f, tries=3, base=0.15):
    """Retry with exponential backoff + jitter"""
    for i in range(tries):
        try:
            return f()
        except Exception as e:
            if i == tries-1:
                raise
            time.sleep(base*(2**i)+random.random()*0.05)

class SB:
    """Supabase singleton client manager"""
    _client: Optional[Client] = None
    _lock = asyncio.Lock()

    @classmethod
    async def client(cls) -> Client:
        """Get or create singleton Supabase client"""
        if cls._client is None:
            async with cls._lock:
                if cls._client is None:
                    url = os.environ.get("SUPABASE_URL", "")
                    key = os.environ.get("SUPABASE_KEY", "")

                    # Warn if pooling not configured
                    if url and "pgbouncer=true" not in url and "pooler" not in url:
                        logger.warning("⚠️ SUPABASE_URL missing pooling params (pgbouncer=true)")

                    cls._client = create_client(url, key)
                    logger.info("✅ Supabase client initialized")
        return cls._client

    @classmethod
    async def ping(cls) -> bool:
        """Lightweight health probe using dedicated table"""
        try:
            c = await cls.client()
            r = c.table("health_probe").select("id").limit(1).execute()
            return r.data is not None
        except Exception as e:
            logger.error(f"Health probe failed: {e}")
            return False

    @classmethod
    async def dispose(cls):
        """Clean up client if needed"""
        cls._client = None
        logger.info("Supabase client disposed")