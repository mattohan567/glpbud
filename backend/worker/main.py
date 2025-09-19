import os
import time
import json
import anthropic
from langfuse import Langfuse
from supabase import create_client
from datetime import datetime

ANTHROPIC_API_KEY = os.environ["ANTHROPIC_API_KEY"]
client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

langfuse = Langfuse(
    public_key=os.environ.get("LANGFUSE_PUBLIC_KEY"),
    secret_key=os.environ.get("LANGFUSE_SECRET_KEY"),
    host=os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com")
)

supabase = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_KEY"]
)

SYSTEM_ORCHESTRATOR = """You are the Orchestrator for "GLP-1 Coach," an iOS-first weight management app.
Objectives: (1) minimize user friction to log meals/exercise/meds, (2) ensure safety and supportive tone,
(3) return STRICT JSON per tool specs, (4) keep costs low by defaulting to cheaper models and escalating only on low confidence.

Principles:
- Prefer single, targeted clarification question if confidence < 0.6.
- Never prescribe medication changes; include disclaimers when discussing GLP-1.
- Log ALL tool calls with intent, inputs (redacted PII), outputs, and confidence.
- Respect unit normalization (g, ml, cup, tbsp) and USDA mappings when possible.
- If user corrected a similar item before, reuse their alias mapping.

When parsing meals, return JSON in this exact format:
{
  "items": [
    {
      "name": "food item name",
      "qty": 100,
      "unit": "g",
      "kcal": 200,
      "protein_g": 20,
      "carbs_g": 10,
      "fat_g": 5
    }
  ],
  "totals": {
    "kcal": 200,
    "protein_g": 20,
    "carbs_g": 10,
    "fat_g": 5
  },
  "confidence": 0.85
}
"""

TOOLS = [
    {
        "name": "vision_nutrition",
        "description": "Parse meal photo into items/macros with confidence.",
        "input_schema": {
            "type": "object",
            "properties": {
                "image_url": {"type": "string"},
                "hints": {"type": "string"}
            },
            "required": ["image_url"]
        }
    },
    {
        "name": "text_nutrition",
        "description": "Parse text meal into items/macros with USDA mapping where possible.",
        "input_schema": {
            "type": "object",
            "properties": {"text": {"type": "string"}},
            "required": ["text"]
        }
    },
    {
        "name": "exercise_estimator",
        "description": "Estimate calories using MET and user weight.",
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string"},
                "duration_min": {"type": "number"},
                "intensity": {"type": "string"},
                "weight_kg": {"type": "number"}
            },
            "required": ["text"]
        }
    }
]

def call_claude_vision(image_url: str, hints: str = None):
    # Langfuse tracking disabled - uncomment to re-enable
    # tr = langfuse.trace(name="vision_nutrition")
    start = time.time()

    try:
        msg = client.messages.create(
            model="claude-3-5-sonnet-20241022",
            max_tokens=1200,
            system=SYSTEM_ORCHESTRATOR,
            messages=[{
                "role": "user",
                "content": [
                    {"type": "text", "text": "Parse this meal photo into items/macros JSON"},
                    {"type": "image", "source": {"type": "url", "url": image_url}},
                    {"type": "text", "text": f"Hints: {hints or 'none'}"}
                ]
            }],
        )

        latency = int((time.time() - start) * 1000)

        # Langfuse tracking disabled - uncomment to re-enable
        # tr.update(
        #     output=msg.content[0].text,
        #     model="sonnet",
        #     metadata={"image_url": image_url, "latency_ms": latency}
        # )
        # tr.end()

        # Log tool run
        supabase.table("tool_runs").insert({
            "tool_name": "vision_nutrition",
            "input": {"image_url": image_url, "hints": hints},
            "output": {"success": True},
            "model": "claude-3-5-sonnet-20241022",
            "latency_ms": latency,
            "cost_usd": 0.001,
            "success": True
        }).execute()

        return json.loads(msg.content[0].text)

    except Exception as e:
        # Langfuse tracking disabled - uncomment to re-enable
        # tr.update(level="ERROR", metadata={"error": str(e)})
        # tr.end()
            
            supabase.table("tool_runs").insert({
                "tool_name": "vision_nutrition",
                "input": {"image_url": image_url},
                "output": None,
                "model": "claude-3-5-sonnet-20241022",
                "latency_ms": int((time.time() - start) * 1000),
                "cost_usd": 0.0,
                "success": False,
                "error": str(e)
            }).execute()
            
            raise

def call_claude_text(text: str, hints: str = None, use_haiku: bool = True):
    model = "claude-3-5-haiku-20241022" if use_haiku else "claude-3-5-sonnet-20241022"

    # Langfuse tracking disabled - uncomment to re-enable
    # tr = langfuse.trace(name="text_nutrition")
    start = time.time()

    try:
        msg = client.messages.create(
            model=model,
            max_tokens=800,
            system=SYSTEM_ORCHESTRATOR,
            messages=[{
                "role": "user",
                "content": f"Parse this meal description into items/macros JSON: {text}\nHints: {hints or 'none'}"
            }],
        )

        latency = int((time.time() - start) * 1000)

        # Langfuse tracking disabled - uncomment to re-enable
        # tr.update(
        #     output=msg.content[0].text,
        #     model=model,
        #     metadata={"text": text[:100], "latency_ms": latency}
        # )

        result = json.loads(msg.content[0].text)

        # If low confidence, escalate to Sonnet
        if use_haiku and result.get("confidence", 1.0) < 0.6:
            # tr.end()  # Langfuse disabled
            return call_claude_text(text, hints, use_haiku=False)

        # tr.end()  # Langfuse disabled

        # Log tool run
        supabase.table("tool_runs").insert({
            "tool_name": "text_nutrition",
            "input": {"text": text[:200], "hints": hints},
            "output": {"confidence": result.get("confidence")},
            "model": model,
            "latency_ms": latency,
            "cost_usd": 0.0005 if use_haiku else 0.001,
            "success": True
        }).execute()

        return result

    except Exception as e:
        # Langfuse tracking disabled - uncomment to re-enable
        # tr.update(level="ERROR", metadata={"error": str(e)})
        # tr.end()
        raise

def process_job(job):
    """Process a single job from the queue."""
    payload = job.get("payload", {})
    job_type = job.get("type")
    user_id = job.get("user_id")
    
    try:
        if job_type == "parse_meal_image":
            result = call_claude_vision(
                payload["image_url"],
                payload.get("hints")
            )
            
            # Save parsed meal to database
            supabase.table("meals").insert({
                "user_id": user_id,
                "ts": datetime.now().isoformat(),
                "source": "image",
                "image_url": payload["image_url"],
                "items": result["items"],
                "totals": result["totals"],
                "confidence": result["confidence"],
                "low_confidence": result.get("confidence", 1.0) < 0.6
            }).execute()
            
        elif job_type == "parse_meal_text":
            result = call_claude_text(
                payload["text"],
                payload.get("hints")
            )
            
            # Save parsed meal to database
            supabase.table("meals").insert({
                "user_id": user_id,
                "ts": datetime.now().isoformat(),
                "source": "text",
                "text_raw": payload["text"],
                "items": result["items"],
                "totals": result["totals"],
                "confidence": result["confidence"],
                "low_confidence": result.get("confidence", 1.0) < 0.6
            }).execute()
        
        # Mark event as processed
        supabase.table("event_bus").update({
            "processed_at": datetime.now().isoformat()
        }).eq("id", job["id"]).execute()
        
        print(f"Processed job {job['id']} successfully")
        
    except Exception as e:
        print(f"Error processing job {job['id']}: {e}")
        # Log error but don't mark as processed so it can be retried

def run_worker():
    """Main worker loop."""
    print("Worker started. Polling for jobs...")
    
    while True:
        try:
            # Fetch unprocessed events
            result = supabase.table("event_bus").select("*").is_(
                "processed_at", "null"
            ).limit(1).execute()
            
            if result.data:
                for job in result.data:
                    process_job(job)
            else:
                time.sleep(1)  # No jobs, wait before polling again
                
        except Exception as e:
            print(f"Worker error: {e}")
            time.sleep(5)  # Wait longer on error

if __name__ == "__main__":
    run_worker()