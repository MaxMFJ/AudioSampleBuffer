#!/usr/bin/env python3
"""Convert the official TensorFlow YAMNet checkpoint to a Core ML package."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import coremltools as ct
import numpy as np
import tensorflow as tf
from tf_keras import Input, Model


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path, help="directory containing yamnet.py, params.py, and yamnet.h5")
    parser.add_argument("output", type=Path, help="output .mlpackage path")
    args = parser.parse_args()

    sys.path.insert(0, str(args.source_dir.resolve()))
    import params  # noqa: PLC0415
    import yamnet  # noqa: PLC0415

    config = params.Params()
    features = Input(shape=(config.patch_frames, config.patch_bands), name="features")
    scores, _ = yamnet.yamnet(features, config)
    model = Model(features, scores)
    model.load_weights(str(args.source_dir / "yamnet.h5"))

    # coremltools 9 currently consumes a SavedModel more reliably than the
    # tf_keras model object; write all intermediate assets under the source dir.
    saved_model = args.source_dir / "saved_model_for_coreml"
    tf.saved_model.save(model, str(saved_model))
    converted = ct.convert(
        str(saved_model),
        source="tensorflow",
        inputs=[ct.TensorType(name="features", shape=(1, 96, 64), dtype=np.float16)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    converted.save(str(args.output))
    print(f"Saved {args.output}")


if __name__ == "__main__":
    main()
