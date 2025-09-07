import anthropic
import os
import time
import json

try:
    from langfuse import Langfuse
    langfuse = Langfuse(
        public_key=os.environ.get("LANGFUSE_PUBLIC_KEY"),
        secret_key=os.environ.get("LANGFUSE_SECRET_KEY"),
        host=os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com")
    ) if os.environ.get("LANGFUSE_PUBLIC_KEY") else None
except ImportError:
    langfuse = None

client = anthropic.Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY")) if os.environ.get("ANTHROPIC_API_KEY") else None

SYSTEM_ORCHESTRATOR = """You are the Orchestrator for "GLP-1 Coach," an iOS-first weight management app.
Objectives: (1) minimize user friction to log meals/exercise/meds, (2) ensure safety and supportive tone,
(3) return STRICT JSON per tool specs, (4) keep costs low by defaulting to cheaper models and escalating only on low confidence.

Principles:
- Prefer single, targeted clarification question if confidence < 0.6.
- Never prescribe medication changes; include disclaimers when discussing GLP-1.
- Log ALL tool calls with intent, inputs (redacted PII), outputs, and confidence.
- Respect unit normalization (g, ml, cup, tbsp) and USDA mappings when possible.
- If user corrected a similar item before, reuse their alias mapping.
"""

def claude_call(messages, model="claude-3-5-haiku-20241022", system=None, tools=None, metadata=None):
    start = time.time()
    trace = langfuse.trace(name="claude_call", metadata=metadata or {}) if langfuse else None
    
    try:
        if not client:
            # Return a mock response when no API key is configured
            class MockMessage:
                content = [type('obj', (object,), {'text': 'I can help with that! For a nutritious breakfast, consider eggs, Greek yogurt, cottage cheese, or lean meats like turkey bacon.'})]
                usage = type('obj', (object,), {'input_tokens': 10, 'output_tokens': 20})
            return MockMessage()
        
        kwargs = {
            'model': model,
            'max_tokens': 1000,
            'system': system or SYSTEM_ORCHESTRATOR,
            'messages': messages
        }
        if tools:
            kwargs['tools'] = tools
        resp = client.messages.create(**kwargs)
        
        latency = int((time.time() - start) * 1000)
        
        if trace:
            trace.update(
                output=resp.content[0].text if resp.content else None,
                model=model,
                metadata={
                    **(metadata or {}),
                    "latency_ms": latency,
                    "usage": {
                        "input_tokens": resp.usage.input_tokens if hasattr(resp, 'usage') else 0,
                        "output_tokens": resp.usage.output_tokens if hasattr(resp, 'usage') else 0
                    }
                }
            )
        
        log_tool_run(
            tool_name="claude_call",
            input_data={"messages": len(messages), "model": model},
            output_data={"success": True},
            model=model,
            latency_ms=latency,
            success=True
        )
        
        return resp
    except Exception as e:
        if trace:
            trace.update(
                level="ERROR",
                metadata={**(metadata or {}), "error": str(e)}
            )
        
        log_tool_run(
            tool_name="claude_call",
            input_data={"messages": len(messages), "model": model},
            output_data=None,
            model=model,
            latency_ms=int((time.time() - start) * 1000),
            success=False,
            error=str(e)
        )
        
        raise

def log_tool_run(tool_name, input_data, output_data, model, latency_ms, success, error=None, user_id=None):
    from supabase import create_client
    
    supabase = create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_KEY"]
    )
    
    try:
        supabase.table("tool_runs").insert({
            "user_id": user_id,
            "tool_name": tool_name,
            "input": input_data,
            "output": output_data,
            "model": model,
            "latency_ms": latency_ms,
            "cost_usd": calculate_cost(model, input_data, output_data),
            "success": success,
            "error": error
        }).execute()
    except Exception as e:
        print(f"Failed to log tool run: {e}")

def calculate_cost(model, input_data, output_data):
    costs = {
        "claude-3-5-haiku-20241022": {"input": 0.001, "output": 0.005},
        "claude-3-5-sonnet-20241022": {"input": 0.003, "output": 0.015}
    }
    
    if model not in costs:
        return 0.0
    
    return 0.001