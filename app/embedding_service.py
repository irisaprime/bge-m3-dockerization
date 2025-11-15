"""
BGE-M3 Embedding Service
=========================
Wrapper for BGE-M3 model with ONNX and PyTorch support
Optimized for CPU inference in air-gapped environments
"""

import os
import logging
from typing import List, Dict, Any, Optional, Union
from dataclasses import dataclass

import numpy as np
from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)


@dataclass
class EmbeddingConfig:
    """Configuration for BGE-M3 embedding service."""

    model_path: str = os.getenv("MODEL_PATH", "/models/bge-m3")
    onnx_model_path: str = os.getenv("ONNX_MODEL_PATH", "/models/bge-m3-onnx")
    use_onnx: bool = os.getenv("USE_ONNX", "true").lower() == "true"
    max_seq_length: int = int(os.getenv("MAX_SEQ_LENGTH", "8192"))
    device: str = "cpu"  # Enforced CPU-only for security
    batch_size: int = int(os.getenv("MAX_BATCH_SIZE", "32"))
    normalize_embeddings: bool = True


class EmbeddingService:
    """
    BGE-M3 Embedding Service with CPU optimization.

    Features:
    - Dense embeddings (1024 dimensions)
    - Sparse embeddings (lexical matching)
    - Multi-vector embeddings (ColBERT)
    - ONNX Runtime support for CPU optimization
    - Memory-efficient batching
    """

    def __init__(self, config: EmbeddingConfig):
        """
        Initialize the embedding service.

        Args:
            config: EmbeddingConfig with model paths and settings
        """
        self.config = config
        self.model = None
        self._load_model()

    def _load_model(self):
        """Load BGE-M3 model with appropriate backend."""
        try:
            if self.config.use_onnx and os.path.exists(self.config.onnx_model_path):
                logger.info(f"Loading ONNX model from {self.config.onnx_model_path}")
                self.model = self._load_onnx_model()
            else:
                logger.info(f"Loading PyTorch model from {self.config.model_path}")
                self.model = self._load_pytorch_model()

            logger.info("Model loaded successfully")
            logger.info(f"Max sequence length: {self.config.max_seq_length}")
            logger.info(f"Device: {self.config.device}")

        except Exception as e:
            logger.error(f"Failed to load model: {e}", exc_info=True)
            raise RuntimeError(f"Model loading failed: {e}")

    def _load_pytorch_model(self) -> SentenceTransformer:
        """Load BGE-M3 model with PyTorch backend."""
        try:
            model = SentenceTransformer(
                self.config.model_path,
                device=self.config.device
            )

            # Set max sequence length
            if hasattr(model, 'max_seq_length'):
                model.max_seq_length = self.config.max_seq_length

            return model

        except Exception as e:
            logger.error(f"PyTorch model loading failed: {e}")
            raise

    def _load_onnx_model(self) -> SentenceTransformer:
        """
        Load BGE-M3 model with ONNX Runtime backend.

        ONNX provides significant CPU performance improvements:
        - 2-4x faster inference on Intel/AMD CPUs
        - Lower memory footprint
        - Better for production deployments
        """
        try:
            # Try loading with Optimum ONNX backend
            from optimum.onnxruntime import ORTModelForFeatureExtraction
            from transformers import AutoTokenizer

            # Load tokenizer
            tokenizer = AutoTokenizer.from_pretrained(self.config.onnx_model_path)

            # Load ONNX model
            model = ORTModelForFeatureExtraction.from_pretrained(
                self.config.onnx_model_path,
                provider="CPUExecutionProvider"  # Enforce CPU
            )

            # Create SentenceTransformer wrapper
            # Note: This is a simplified approach
            # For full BGE-M3 functionality, use the native implementation

            logger.info("ONNX model loaded with CPUExecutionProvider")
            return self._create_onnx_wrapper(model, tokenizer)

        except ImportError:
            logger.warning("Optimum ONNX not available, falling back to PyTorch")
            return self._load_pytorch_model()
        except Exception as e:
            logger.error(f"ONNX model loading failed: {e}")
            logger.warning("Falling back to PyTorch model")
            return self._load_pytorch_model()

    def _create_onnx_wrapper(self, onnx_model, tokenizer):
        """
        Create a wrapper around ONNX model to match SentenceTransformer interface.

        For production, consider using a dedicated BGE-M3 ONNX implementation
        like: https://github.com/yuniko-software/bge-m3-onnx
        """
        class ONNXModelWrapper:
            def __init__(self, model, tokenizer, device="cpu"):
                self.model = model
                self.tokenizer = tokenizer
                self.device = device

            def encode(self, sentences, batch_size=32, normalize_embeddings=True, **kwargs):
                """Encode sentences to embeddings using ONNX model."""
                if isinstance(sentences, str):
                    sentences = [sentences]

                all_embeddings = []

                for i in range(0, len(sentences), batch_size):
                    batch = sentences[i:i + batch_size]

                    # Tokenize
                    encoded = self.tokenizer(
                        batch,
                        padding=True,
                        truncation=True,
                        max_length=8192,
                        return_tensors="pt"
                    )

                    # Run inference
                    outputs = self.model(**encoded)

                    # Mean pooling
                    embeddings = self._mean_pooling(
                        outputs.last_hidden_state,
                        encoded['attention_mask']
                    )

                    # Normalize if requested
                    if normalize_embeddings:
                        embeddings = embeddings / np.linalg.norm(
                            embeddings, axis=1, keepdims=True
                        )

                    all_embeddings.append(embeddings)

                result = np.vstack(all_embeddings)
                return result

            def _mean_pooling(self, token_embeddings, attention_mask):
                """Mean pooling with attention mask."""
                input_mask_expanded = np.expand_dims(
                    attention_mask.numpy(), -1
                ).astype(float)

                sum_embeddings = np.sum(
                    token_embeddings.numpy() * input_mask_expanded, axis=1
                )
                sum_mask = np.clip(input_mask_expanded.sum(axis=1), a_min=1e-9, a_max=None)

                return sum_embeddings / sum_mask

        return ONNXModelWrapper(onnx_model, tokenizer, self.config.device)

    def encode(
        self,
        texts: List[str],
        return_dense: bool = True,
        return_sparse: bool = False,
        return_colbert: bool = False,
        normalize: bool = True
    ) -> List[Union[List[float], Dict[str, Any]]]:
        """
        Generate embeddings for input texts.

        Args:
            texts: List of input texts
            return_dense: Return dense embeddings (1024 dims)
            return_sparse: Return sparse embeddings
            return_colbert: Return ColBERT multi-vector embeddings
            normalize: L2 normalize dense embeddings

        Returns:
            List of embedding vectors (format depends on flags)
        """
        if not texts:
            raise ValueError("Input texts cannot be empty")

        if len(texts) > self.config.batch_size:
            raise ValueError(
                f"Batch size ({len(texts)}) exceeds maximum ({self.config.batch_size})"
            )

        try:
            # For now, we primarily support dense embeddings
            # Full BGE-M3 with sparse/ColBERT requires the FlagEmbedding library
            if return_dense:
                embeddings = self.model.encode(
                    texts,
                    batch_size=self.config.batch_size,
                    normalize_embeddings=normalize,
                    convert_to_numpy=True
                )

                # Convert to list for JSON serialization
                result = embeddings.tolist()

                # If sparse or ColBERT requested, add placeholder
                # (requires FlagEmbedding library for full implementation)
                if return_sparse or return_colbert:
                    logger.warning(
                        "Sparse and ColBERT embeddings require FlagEmbedding library. "
                        "Returning dense embeddings only."
                    )

                return result

            else:
                raise ValueError("At least one embedding type must be requested")

        except Exception as e:
            logger.error(f"Embedding generation failed: {e}", exc_info=True)
            raise RuntimeError(f"Embedding generation failed: {e}")

    def encode_queries(self, queries: List[str], **kwargs) -> np.ndarray:
        """Encode queries (convenience method)."""
        return self.encode(queries, **kwargs)

    def encode_documents(self, documents: List[str], **kwargs) -> np.ndarray:
        """Encode documents (convenience method)."""
        return self.encode(documents, **kwargs)

    def get_embedding_dimension(self) -> int:
        """Get embedding dimension."""
        return 1024  # BGE-M3 dense embedding dimension

    def get_model_info(self) -> Dict[str, Any]:
        """Get model information."""
        return {
            "model_name": "BAAI/bge-m3",
            "backend": "onnx" if self.config.use_onnx else "pytorch",
            "device": self.config.device,
            "max_seq_length": self.config.max_seq_length,
            "embedding_dimension": self.get_embedding_dimension(),
            "supports_dense": True,
            "supports_sparse": False,  # Requires FlagEmbedding
            "supports_colbert": False,  # Requires FlagEmbedding
        }


# =============================================================================
# Enhanced BGE-M3 Implementation (Optional)
# =============================================================================

class BGE_M3_Enhanced:
    """
    Enhanced BGE-M3 implementation with full sparse/ColBERT support.

    This requires the FlagEmbedding library which is not included by default
    for security reasons. For full functionality, add to requirements.txt:
        FlagEmbedding==1.2.10

    Usage:
        from FlagEmbedding import BGEM3FlagModel
        model = BGEM3FlagModel(model_path, use_fp16=False)
        embeddings = model.encode(
            texts,
            return_dense=True,
            return_sparse=True,
            return_colbert_vecs=True
        )
    """
    pass
