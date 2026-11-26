/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */

/// Provider-owned mapping and row materialization contracts for Flint AOT.
module flint.engine.jpa;

public import flint.engine.jpa.mapping : AttributeKind, AttributeMapping, AttributeValue,
    EntityMapping, LifecycleCallback, validateEntity, validateMapping;
public import flint.engine.jpa.result_binding : ResultBinding, RowMaterializationPlan, materializeRow, planResult;

@safe:
