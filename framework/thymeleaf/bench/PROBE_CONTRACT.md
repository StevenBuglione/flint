# Flint Thymeleaf probe

The fixture resolves the Thymeleaf mode name `HTML` with no command-line arguments and `TEXT` with an extra argument. It prints the declared name, content classification and case sensitivity. The control declares the same direct dependencies, `flint:java` and `flint:engine-aot`, and prints the corresponding result for each input.

Both programs print `HTML markup insensitive` or `TEXT text sensitive` followed by a newline. The size probe uses O3 and Oz loadable bytes, and the template probe counts DMD instantiations in the application and its Thymeleaf library.
