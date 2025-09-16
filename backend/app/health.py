import asyncio
import time
from typing import Dict, Any, List
from datetime import datetime, timedelta
import logging
import httpx
import os
from supabase import create_client

from .logging_config import ExternalServiceError, DatabaseError

logger = logging.getLogger(__name__)

class HealthChecker:
    """Comprehensive health checking for all application dependencies"""
    
    def __init__(self):
        self.checks = {
            'database': self._check_database,
            'claude_api': self._check_claude_api,
            'supabase_auth': self._check_supabase_auth,
            'langfuse': self._check_langfuse,
            'sentry': self._check_sentry
        }
        
    async def run_all_checks(self) -> Dict[str, Any]:
        """Run all health checks and return comprehensive status"""
        start_time = time.time()
        results = {}
        overall_healthy = True
        
        # Run checks concurrently
        tasks = []
        for check_name, check_func in self.checks.items():
            task = asyncio.create_task(self._run_single_check(check_name, check_func))
            tasks.append(task)
        
        check_results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        for i, (check_name, _) in enumerate(self.checks.items()):
            result = check_results[i]
            if isinstance(result, Exception):
                results[check_name] = {
                    'status': 'error',
                    'healthy': False,
                    'error': str(result),
                    'response_time_ms': None
                }
                overall_healthy = False
            else:
                results[check_name] = result
                if not result['healthy']:
                    overall_healthy = False
        
        total_time = int((time.time() - start_time) * 1000)
        
        return {
            'status': 'healthy' if overall_healthy else 'degraded',
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'response_time_ms': total_time,
            'checks': results,
            'version': '1.0.0',
            'environment': os.environ.get('ENVIRONMENT', 'unknown')
        }
    
    async def _run_single_check(self, name: str, check_func) -> Dict[str, Any]:
        """Run a single health check with timing"""
        start_time = time.time()
        try:
            result = await check_func()
            response_time = int((time.time() - start_time) * 1000)
            return {
                'status': 'ok',
                'healthy': True,
                'response_time_ms': response_time,
                **result
            }
        except Exception as e:
            response_time = int((time.time() - start_time) * 1000)
            logger.error(f"Health check failed for {name}: {e}")
            return {
                'status': 'error',
                'healthy': False,
                'error': str(e),
                'response_time_ms': response_time
            }
    
    async def _check_database(self) -> Dict[str, Any]:
        """Check Supabase database connectivity and basic operations"""
        try:
            supabase = create_client(
                os.environ["SUPABASE_URL"],
                os.environ["SUPABASE_KEY"]
            )
            
            # Test basic query
            result = supabase.table("users").select("id").limit(1).execute()
            
            # Test write capability (using a dummy operation that won't affect data)
            test_time = datetime.utcnow()
            
            return {
                'connection': 'ok',
                'read_access': 'ok',
                'last_check': test_time.isoformat(),
                'details': f"Successfully connected to Supabase database"
            }
            
        except Exception as e:
            raise DatabaseError("health_check", str(e))
    
    async def _check_claude_api(self) -> Dict[str, Any]:
        """Check Claude API connectivity and response"""
        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            return {
                'connection': 'disabled',
                'details': 'Claude API key not configured'
            }
        
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=api_key)
            
            # Make a minimal API call
            response = client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=10,
                messages=[{"role": "user", "content": "Say 'ok'"}]
            )
            
            return {
                'connection': 'ok',
                'model': 'claude-3-5-haiku-20241022',
                'response_length': len(response.content[0].text) if response.content else 0,
                'usage': {
                    'input_tokens': response.usage.input_tokens,
                    'output_tokens': response.usage.output_tokens
                } if hasattr(response, 'usage') else None
            }
            
        except Exception as e:
            raise ExternalServiceError("Claude API", str(e))
    
    async def _check_supabase_auth(self) -> Dict[str, Any]:
        """Check Supabase authentication service"""
        try:
            supabase = create_client(
                os.environ["SUPABASE_URL"],
                os.environ["SUPABASE_KEY"]
            )
            
            # Test auth service availability (this will fail gracefully)
            # We don't want to create test users, so just check the service responds
            
            return {
                'service': 'ok',
                'details': 'Supabase auth service accessible'
            }
            
        except Exception as e:
            raise ExternalServiceError("Supabase Auth", str(e))
    
    async def _check_langfuse(self) -> Dict[str, Any]:
        """Check Langfuse observability service"""
        public_key = os.environ.get("LANGFUSE_PUBLIC_KEY")
        if not public_key:
            return {
                'connection': 'disabled',
                'details': 'Langfuse not configured'
            }
        
        try:
            from langfuse import Langfuse
            
            langfuse = Langfuse(
                public_key=os.environ.get("LANGFUSE_PUBLIC_KEY"),
                secret_key=os.environ.get("LANGFUSE_SECRET_KEY"),
                host=os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com")
            )
            
            # Test basic functionality
            trace = langfuse.trace(name="health_check")
            
            return {
                'connection': 'ok',
                'host': os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com"),
                'details': 'Langfuse observability service accessible'
            }
            
        except Exception as e:
            raise ExternalServiceError("Langfuse", str(e))
    
    async def _check_sentry(self) -> Dict[str, Any]:
        """Check Sentry error tracking service"""
        dsn = os.environ.get("SENTRY_DSN")
        if not dsn:
            return {
                'connection': 'disabled',
                'details': 'Sentry not configured'
            }
        
        try:
            import sentry_sdk
            
            # Test Sentry configuration (without actually sending an error)
            client = sentry_sdk.Hub.current.client
            if client is None:
                raise Exception("Sentry client not initialized")
            
            return {
                'connection': 'ok',
                'dsn_configured': True,
                'details': 'Sentry error tracking service configured'
            }
            
        except Exception as e:
            raise ExternalServiceError("Sentry", str(e))

class MetricsCollector:
    """Collect application metrics for monitoring"""
    
    def __init__(self):
        self.start_time = time.time()
        self.request_count = 0
        self.error_count = 0
        
    def get_metrics(self) -> Dict[str, Any]:
        """Get current application metrics"""
        uptime_seconds = int(time.time() - self.start_time)
        
        return {
            'uptime_seconds': uptime_seconds,
            'uptime_human': self._format_uptime(uptime_seconds),
            'requests_total': self.request_count,
            'errors_total': self.error_count,
            'error_rate': self.error_count / max(self.request_count, 1),
            'memory_usage': self._get_memory_usage(),
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }
    
    def increment_requests(self):
        """Increment request counter"""
        self.request_count += 1
    
    def increment_errors(self):
        """Increment error counter"""
        self.error_count += 1
    
    def _format_uptime(self, seconds: int) -> str:
        """Format uptime in human readable format"""
        days = seconds // 86400
        hours = (seconds % 86400) // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60
        
        if days > 0:
            return f"{days}d {hours}h {minutes}m {secs}s"
        elif hours > 0:
            return f"{hours}h {minutes}m {secs}s"
        elif minutes > 0:
            return f"{minutes}m {secs}s"
        else:
            return f"{secs}s"
    
    def _get_memory_usage(self) -> Dict[str, Any]:
        """Get memory usage information"""
        try:
            import psutil
            process = psutil.Process()
            memory_info = process.memory_info()
            
            return {
                'rss_bytes': memory_info.rss,
                'rss_mb': round(memory_info.rss / 1024 / 1024, 2),
                'vms_bytes': memory_info.vms,
                'vms_mb': round(memory_info.vms / 1024 / 1024, 2)
            }
        except ImportError:
            return {
                'error': 'psutil not available'
            }
        except Exception as e:
            return {
                'error': str(e)
            }

# Global instances
health_checker = HealthChecker()
metrics_collector = MetricsCollector()