import logging
import sys
import os
from typing import Dict, Any, Optional
import traceback
from datetime import datetime
import json

# Configure structured logging
class StructuredFormatter(logging.Formatter):
    """Custom formatter for structured JSON logging"""
    
    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "module": record.module,
            "function": record.funcName,
            "line": record.lineno,
        }
        
        # Add extra fields if present
        if hasattr(record, 'user_id'):
            log_entry['user_id'] = record.user_id
        if hasattr(record, 'request_id'):
            log_entry['request_id'] = record.request_id
        if hasattr(record, 'endpoint'):
            log_entry['endpoint'] = record.endpoint
        if hasattr(record, 'execution_time'):
            log_entry['execution_time_ms'] = record.execution_time
            
        # Add exception details if present
        if record.exc_info:
            log_entry['exception'] = {
                "type": record.exc_info[0].__name__,
                "message": str(record.exc_info[1]),
                "traceback": traceback.format_exception(*record.exc_info)
            }
            
        return json.dumps(log_entry)

def setup_logging():
    """Configure application logging"""
    
    # Get log level from environment
    log_level = os.environ.get("LOG_LEVEL", "INFO").upper()
    
    # Create root logger
    logger = logging.getLogger()
    logger.setLevel(getattr(logging, log_level))
    
    # Remove default handlers
    for handler in logger.handlers[:]:
        logger.removeHandler(handler)
    
    # Create console handler with structured formatting
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(StructuredFormatter())
    logger.addHandler(console_handler)
    
    # Silence some noisy loggers
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("httpcore").setLevel(logging.WARNING)
    logging.getLogger("urllib3").setLevel(logging.WARNING)
    
    return logger

# Application error classes
class AppError(Exception):
    """Base application error"""
    def __init__(self, message: str, error_code: str = None, details: Dict[str, Any] = None):
        self.message = message
        self.error_code = error_code or "GENERAL_ERROR"
        self.details = details or {}
        super().__init__(self.message)

class ValidationError(AppError):
    """Input validation error"""
    def __init__(self, message: str, field: str = None, details: Dict[str, Any] = None):
        super().__init__(message, "VALIDATION_ERROR", details)
        self.field = field

class AuthenticationError(AppError):
    """Authentication error"""
    def __init__(self, message: str = "Authentication required"):
        super().__init__(message, "AUTH_ERROR")

class AuthorizationError(AppError):
    """Authorization error"""
    def __init__(self, message: str = "Access denied"):
        super().__init__(message, "AUTHZ_ERROR")

class ExternalServiceError(AppError):
    """External service error (Claude API, Supabase, etc.)"""
    def __init__(self, service: str, message: str, status_code: int = None):
        super().__init__(f"{service} error: {message}", "EXTERNAL_SERVICE_ERROR", {
            "service": service,
            "status_code": status_code
        })

class DatabaseError(AppError):
    """Database operation error"""
    def __init__(self, operation: str, message: str):
        super().__init__(f"Database {operation} failed: {message}", "DATABASE_ERROR", {
            "operation": operation
        })

# Error reporting utilities
def log_error(logger: logging.Logger, error: Exception, context: Dict[str, Any] = None):
    """Log an error with context"""
    context = context or {}
    
    if isinstance(error, AppError):
        logger.error(
            f"Application error: {error.message}",
            extra={
                "error_code": error.error_code,
                "error_details": error.details,
                **context
            },
            exc_info=True
        )
    else:
        logger.error(
            f"Unexpected error: {str(error)}",
            extra=context,
            exc_info=True
        )

def log_api_call(logger: logging.Logger, 
                endpoint: str, 
                user_id: str = None, 
                execution_time: float = None,
                status_code: int = None,
                request_size: int = None,
                response_size: int = None):
    """Log API call metrics"""
    logger.info(
        f"API call completed: {endpoint}",
        extra={
            "endpoint": endpoint,
            "user_id": user_id,
            "execution_time": execution_time,
            "status_code": status_code,
            "request_size": request_size,
            "response_size": response_size
        }
    )

# Initialize logging
app_logger = setup_logging()