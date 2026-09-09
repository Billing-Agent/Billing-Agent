class BillingAgentException(Exception):
    """Base exception for all domain exceptions."""
    pass

class EntityNotFoundError(BillingAgentException):
    """Raised when an entity is not found."""
    pass

class BusinessLogicError(BillingAgentException):
    """Raised when a business logic constraint is violated."""
    pass

class ConcurrencyConflictError(BillingAgentException):
    """Raised when an idempotency conflict or concurrency conflict occurs."""
    pass
