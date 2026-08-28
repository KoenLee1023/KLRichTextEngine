# Architecture and execution model

The package is divided into document, serialization, editing, typography, and UI layers. Serialization converts between `RichTextDocument`, JSON, RTF, and attributed strings. Editing operates on value-type documents and returns a new value. UI adapters render that value and report user actions to the host.

`RichTextDocument`, `RichTextContent`, and the mutation types are value types. They are `Sendable` where their contracts permit it. The host owns persistence and decides when a document is saved or synchronized.

UI entry points and APIs marked `@MainActor` must be used on the main actor. Pure codecs and value transformations do not perform I/O and can be used from an appropriate isolated context. The package does not start synchronization tasks or access a database.

Validation happens before parsing and before mutations that depend on UTF-16 ranges. A rejected or unknown payload remains available through a read-only result so the host can migrate it deliberately.
