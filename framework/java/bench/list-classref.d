module app;

import flint.java.classref : ClassRef, classOf;
import flint.java.util : ArrayList, List;

@safe:

int main(string[] args)
{
    const named = args.length > 1 ? ClassRef(args[1]) : classOf!Object;
    List!ClassRef values = new ArrayList!ClassRef();
    values.add(named);
    values.add(ClassRef.init);
    return cast(int) values.toString().length & 127;
}
