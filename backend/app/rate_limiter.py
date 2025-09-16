import time
from typing import Dict, Tuple
from collections import defaultdict, deque
from fastapi import HTTPException, Request
import hashlib

class RateLimiter:
    """Simple in-memory rate limiter"""
    
    def __init__(self):
        # Format: {identifier: deque of timestamps}
        self.requests = defaultdict(deque)
        self.cleanup_interval = 300  # Clean up every 5 minutes
        self.last_cleanup = time.time()
        
        # Rate limit rules: (requests_per_window, window_seconds)
        self.limits = {
            'default': (100, 60),  # 100 requests per minute
            'auth': (10, 60),      # 10 auth requests per minute
            'parse': (30, 60),     # 30 parse requests per minute (expensive)
            'coach': (20, 60),     # 20 coach requests per minute
            'upload': (5, 60),     # 5 uploads per minute
        }
    
    def get_identifier(self, request: Request, user_id: str = None) -> str:
        """Get unique identifier for rate limiting"""
        if user_id:
            return f"user:{user_id}"
        
        # Fall back to IP address
        client_ip = request.client.host if request.client else "unknown"
        
        # For requests behind a proxy, check common headers
        forwarded_for = request.headers.get("X-Forwarded-For")
        if forwarded_for:
            client_ip = forwarded_for.split(",")[0].strip()
        
        real_ip = request.headers.get("X-Real-IP")
        if real_ip:
            client_ip = real_ip
        
        return f"ip:{client_ip}"
    
    def check_rate_limit(self, identifier: str, limit_type: str = 'default') -> Tuple[bool, Dict]:
        """Check if request is within rate limit"""
        current_time = time.time()
        
        # Clean up old requests periodically
        if current_time - self.last_cleanup > self.cleanup_interval:
            self._cleanup_old_requests(current_time)
            self.last_cleanup = current_time
        
        # Get rate limit for this operation
        max_requests, window_seconds = self.limits.get(limit_type, self.limits['default'])
        
        # Get request history for this identifier
        request_times = self.requests[identifier]
        
        # Remove requests outside the current window
        cutoff_time = current_time - window_seconds
        while request_times and request_times[0] < cutoff_time:
            request_times.popleft()
        
        # Check if we're over the limit
        if len(request_times) >= max_requests:
            # Calculate time until next request is allowed
            oldest_request = request_times[0]
            reset_time = oldest_request + window_seconds
            retry_after = int(reset_time - current_time)
            
            return False, {
                'limit': max_requests,
                'window': window_seconds,
                'current': len(request_times),
                'retry_after': retry_after,
                'reset_time': reset_time
            }
        
        # Add current request
        request_times.append(current_time)
        
        return True, {
            'limit': max_requests,
            'window': window_seconds,
            'current': len(request_times),
            'remaining': max_requests - len(request_times),
            'reset_time': current_time + window_seconds
        }
    
    def _cleanup_old_requests(self, current_time: float):
        """Clean up old request records to prevent memory leaks"""
        max_window = max(window for _, window in self.limits.values())
        cutoff_time = current_time - max_window
        
        # Clean up each identifier's request history
        identifiers_to_remove = []
        for identifier, request_times in self.requests.items():
            # Remove old requests
            while request_times and request_times[0] < cutoff_time:
                request_times.popleft()
            
            # Remove empty deques
            if not request_times:
                identifiers_to_remove.append(identifier)
        
        # Remove empty identifiers
        for identifier in identifiers_to_remove:
            del self.requests[identifier]

# Global rate limiter instance
rate_limiter = RateLimiter()

def check_rate_limit(request: Request, user_id: str = None, limit_type: str = 'default'):
    """Middleware function to check rate limits"""
    identifier = rate_limiter.get_identifier(request, user_id)
    allowed, info = rate_limiter.check_rate_limit(identifier, limit_type)
    
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail={
                "error": "RATE_LIMIT_EXCEEDED",
                "message": f"Rate limit exceeded. Try again in {info['retry_after']} seconds.",
                "limit": info['limit'],
                "window_seconds": info['window'],
                "retry_after": info['retry_after']
            },
            headers={
                "Retry-After": str(info['retry_after']),
                "X-RateLimit-Limit": str(info['limit']),
                "X-RateLimit-Window": str(info['window']),
                "X-RateLimit-Remaining": "0"
            }
        )
    
    return info