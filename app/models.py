"""
Pydantic Models for BGE-M3 Embedding Service
=============================================
Request/response validation and serialization
"""

from typing import List, Optional, Dict, Any, Union
from pydantic import BaseModel, Field, validator


class EmbeddingRequest(BaseModel):
    """Request model for embedding generation."""

    texts: List[str] = Field(
        ...,
        description="List of text strings to embed",
        min_items=1,
        max_items=32,
        example=["Hello, world!", "This is a test."]
    )

    return_dense: bool = Field(
        True,
        description="Return dense embeddings (1024 dimensions)"
    )

    return_sparse: bool = Field(
        False,
        description="Return sparse embeddings for lexical matching"
    )

    return_colbert: bool = Field(
        False,
        description="Return multi-vector ColBERT embeddings"
    )

    normalize: bool = Field(
        True,
        description="L2 normalize dense embeddings"
    )

    @validator('texts')
    def validate_texts(cls, v):
        """Validate text inputs."""
        # Check for empty strings
        if any(not text.strip() for text in v):
            raise ValueError("Empty text strings are not allowed")

        # Check individual text length (8192 tokens ≈ 32,768 chars max)
        max_length = 32768
        for text in v:
            if len(text) > max_length:
                raise ValueError(
                    f"Text length exceeds maximum ({max_length} characters). "
                    f"Please split long texts into smaller chunks."
                )

        return v

    class Config:
        json_schema_extra = {
            "example": {
                "texts": [
                    "What is BGE-M3?",
                    "BGE-M3 is a versatile embedding model supporting dense, sparse, and multi-vector retrieval."
                ],
                "return_dense": True,
                "return_sparse": False,
                "return_colbert": False,
                "normalize": True
            }
        }


class EmbeddingData(BaseModel):
    """Embedding data for a single text."""

    dense: Optional[List[float]] = Field(
        None,
        description="Dense embedding vector (1024 dimensions)"
    )

    sparse: Optional[Dict[int, float]] = Field(
        None,
        description="Sparse embedding (token_id -> weight mapping)"
    )

    colbert: Optional[List[List[float]]] = Field(
        None,
        description="Multi-vector ColBERT embeddings"
    )


class EmbeddingResponse(BaseModel):
    """Response model for embedding generation."""

    embeddings: List[Union[List[float], Dict[str, Any]]] = Field(
        ...,
        description="Generated embeddings for input texts"
    )

    model: str = Field(
        ...,
        description="Model used for embedding generation",
        example="BAAI/bge-m3"
    )

    processing_time: float = Field(
        ...,
        description="Processing time in seconds",
        example=0.123
    )

    count: int = Field(
        ...,
        description="Number of embeddings generated",
        example=2
    )

    class Config:
        json_schema_extra = {
            "example": {
                "embeddings": [
                    [0.123, -0.456, 0.789, "..."],  # 1024 dimensions
                    [0.321, -0.654, 0.987, "..."]
                ],
                "model": "BAAI/bge-m3",
                "processing_time": 0.123,
                "count": 2
            }
        }


class HealthResponse(BaseModel):
    """Health check response."""

    status: str = Field(
        ...,
        description="Service status",
        example="healthy"
    )

    model_loaded: bool = Field(
        ...,
        description="Whether the model is loaded",
        example=True
    )

    version: str = Field(
        ...,
        description="Service version",
        example="1.0.0"
    )


class ErrorResponse(BaseModel):
    """Error response model."""

    error: str = Field(
        ...,
        description="Error message",
        example="Invalid API Key"
    )

    status_code: int = Field(
        ...,
        description="HTTP status code",
        example=403
    )


class MetricsResponse(BaseModel):
    """Metrics response (Prometheus format)."""

    metrics: str = Field(
        ...,
        description="Prometheus-formatted metrics"
    )
