/*
 * Copyright (c) 2026 the Flint authors.
 * SPDX-License-Identifier: Apache-2.0
 */
module member_descriptor_tests;

import flint.engine.aot.descriptor : ConstructorDescriptor, Descriptor, MemberDescriptorRef,
    MemberKind, MergedAnnotation, MethodDescriptor, PropertyDescriptor, TypeKind;

@safe:

private Descriptor ownerFixture()
{
    auto owner = new Descriptor("fixtures.Service", TypeKind.class_);
    owner.methods = [MethodDescriptor("unrelated", "void"), MethodDescriptor("rename", "void")];
    owner.methods[1].annotations = [MergedAnnotation("fixtures.MethodAnnotation")];
    owner.constructors = [ConstructorDescriptor()];
    owner.constructors[0].annotations = [MergedAnnotation("fixtures.ConstructorAnnotation")];
    owner.properties = [PropertyDescriptor("name", "string")];
    owner.properties[0].annotations = [MergedAnnotation("fixtures.PropertyAnnotation")];
    return owner;
}

@("Member descriptors expose the selected method, constructor, or property metadata") unittest
{
    auto owner = ownerFixture();
    const method = MemberDescriptorRef(owner, 1, MemberKind.method);
    const constructor = MemberDescriptorRef(owner, 0, MemberKind.constructor);
    const field = MemberDescriptorRef(owner, 0, MemberKind.field);

    assert(method.method() is &owner.methods[1]);
    assert(method.name() == "rename");
    assert(method.annotations()[0].type == "fixtures.MethodAnnotation");
    assert(method.declaringType() is owner);

    assert(constructor.constructor() is &owner.constructors[0]);
    assert(constructor.name() == "fixtures.Service");
    assert(constructor.annotations()[0].type == "fixtures.ConstructorAnnotation");

    assert(field.field() is &owner.properties[0]);
    assert(field.name() == "name");
    assert(field.annotations()[0].type == "fixtures.PropertyAnnotation");
    assert(field.declaringType() is owner);
}

@("Absent, out-of-range, and mismatched member references return no metadata") unittest
{
    auto owner = ownerFixture();
    const absent = MemberDescriptorRef.init;
    assert(absent.method() is null && absent.constructor() is null && absent.field() is null);
    assert(absent.name() is null && absent.declaringType() is null && absent.annotations() is null);

    const missing = MemberDescriptorRef(owner, 5, MemberKind.method);
    assert(missing.method() is null && missing.annotations() is null && missing.declaringType() is null);
    assert(MemberDescriptorRef(owner, 1, MemberKind.constructor).constructor() is null);
    assert(MemberDescriptorRef(owner, 1, MemberKind.field).field() is null);

    const method = MemberDescriptorRef(owner, 1, MemberKind.method);
    assert(method.constructor() is null && method.field() is null);
    assert(method == MemberDescriptorRef(owner, 1, MemberKind.method));
    assert(method.toHash() == MemberDescriptorRef(owner, 1, MemberKind.method).toHash());
    assert(method != MemberDescriptorRef(owner, 0, MemberKind.method));
    assert(method != MemberDescriptorRef(owner, 1, MemberKind.field));
    assert(method != MemberDescriptorRef(ownerFixture(), 1, MemberKind.method));
}

@("Member index references do not allocate while exposing stable borrowed metadata") unittest
{
    static assert(MemberDescriptorRef.sizeof <= 16);
    const(MethodDescriptor)* getMethod(MemberDescriptorRef member) nothrow @nogc
    {
        return member.method();
    }

    auto owner = ownerFixture();
    const MemberDescriptorRef first = MemberDescriptorRef(owner, 0, MemberKind.method);
    assert(getMethod(first) is &owner.methods[0]);
}
