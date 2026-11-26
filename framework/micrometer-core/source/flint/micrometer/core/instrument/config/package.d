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
// Ported from micrometer-core 1.18.0: micrometer-core/src/main/java/io/micrometer/core/instrument/config/InvalidConfigurationException.java
// Modified by the Flint authors.
module flint.micrometer.core.instrument.config;

import flint.java.lang : IllegalStateException, Integer;

@safe:

/// Invalid input to a Micrometer configuration.
class InvalidConfigurationException : IllegalStateException
{
    /// Keep the diagnostic for the rejected configuration.
    this(string message)
    {
        super(message);
    }

    /// Keep the diagnostic and its original cause.
    this(string message, Throwable cause)
    {
        super(message, cause);
    }
}

/// Check the configured number of distribution buckets before registration.
package(flint.micrometer.core.instrument) void validateDistributionBufferLength(int length)
{
    if (length <= 0)
        throw new InvalidConfigurationException("Invalid distribution configuration: bufferLength (" ~ Integer.toString(
                length) ~ ") must be greater than zero");
}
