// App extensions don't run this: the linker entry point is replaced
// with _NSExtensionMain (see Package.swift), which loads the principal
// class from the Info.plist. This file only satisfies SPM's requirement
// that executable targets have a main.
