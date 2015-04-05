# Features
 - operators are translated to words. As it is now an operator would result in broken code.
 - Stub generation of C-functions.

# Before it is useful
 - Interface method that are const.
 - const parameters in a method.
 - Manager of lifetime for the stub and access to the instance for the tester.
 - Generated data in namespace to avoid name collisions.
 - ctor's. Problem is... a sensible name mangling.

# Quality of Life
 - Data in the stub data struct groups separated by enter.
 - Date in the header when it was generated.
 - Support for header with copyright notice in generated.
 - A pure stub interface that have all callbacks inherited.
