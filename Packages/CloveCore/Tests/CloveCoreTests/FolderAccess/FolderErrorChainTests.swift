import Foundation
import Testing

import CloveCore

@Test func theErrorChainIsPreservedWithUnderlyingErrors() throws {
    let missing = NSError(domain: NSPOSIXErrorDomain, code: 2)
    let readError = NSError(
        domain: NSCocoaErrorDomain, code: 260, userInfo: [NSUnderlyingErrorKey: missing])
    let chain = FolderErrorChain(readError)
    #expect(chain.domain == NSCocoaErrorDomain)
    #expect(chain.code == 260)
    #expect(!chain.message.isEmpty)
    #expect(chain.errors.count == 2)
    #expect(chain.underlying.first?.domain == NSPOSIXErrorDomain)
    #expect(chain.underlying.first?.code == 2)
    #expect(chain.errors.contains { $0.matches(domain: NSPOSIXErrorDomain, code: 2) })
    #expect(chain.summary.contains("260"))
    #expect(chain.summary.contains("underlying:"))
}

@Test func multipleUnderlyingErrorsAreKeptToo() throws {
    let permission = NSError(domain: NSPOSIXErrorDomain, code: 13)
    let readOnly = NSError(domain: NSPOSIXErrorDomain, code: 30)
    let wrapper = NSError(
        domain: NSCocoaErrorDomain, code: 512,
        userInfo: [NSMultipleUnderlyingErrorsKey: [permission, readOnly]])
    let chain = FolderErrorChain(wrapper)
    #expect(chain.underlying.count == 2)
    #expect(chain.errors.contains { $0.matches(domain: NSPOSIXErrorDomain, code: 13) })
    #expect(chain.errors.contains { $0.matches(domain: NSPOSIXErrorDomain, code: 30) })
}
