/*
 * Copyright 2017 VMware, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/internal/Mergeable.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.internal;

@safe:

/// A configuration that supplies unset values from another configuration.
interface Mergeable(T)
{
    /// Merge unset fields from the lower-precedence parent.
    T merge(T parent);

    /// Merge unset fields from a read-only parent, including static defaults.
    T merge(const(T) parent);

    /// Merge when the receiver is itself a read-only configuration.
    T merge(const(T) parent) const;
}
