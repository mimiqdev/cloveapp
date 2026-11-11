import Testing

@testable import CloveCore

@Suite struct FolderDisplayLocationTests {
    @Test func localProviderHidesContainer() {
        let path =
            "/private/var/mobile/Containers/Shared/AppGroup/10000000-0000-0000-0000-000000000001/File Provider Storage/Shoots/2026"
        #expect(
            FolderDisplayLocation.text(path: path, volumeName: nil, mediaType: .internalVolume)
                == "On My iPhone › Shoots › 2026")
        #expect(
            FolderDisplayLocation.text(
                path: path, volumeName: nil, mediaType: .internalVolume, device: "iPad")
                == "On My iPad › Shoots › 2026")
    }

    @Test func userFolderNamesSurviveAfterTheProviderAnchor() {
        let root =
            "/private/var/mobile/Containers/Shared/AppGroup/10000000-0000-0000-0000-000000000001/File Provider Storage"
        let path = root + "/Clients/Shared"
        #expect(FolderDisplayLocation.name(path: path) == "Shared")
        #expect(
            FolderDisplayLocation.text(path: path, volumeName: nil, mediaType: .internalVolume)
                == "On My iPhone › Clients › Shared")
        for name in ["Data", "Shared", "Library", "Application", "mobile"] {
            let local = root + "/Clients/" + name
            #expect(FolderDisplayLocation.name(path: local) == name)
            #expect(
                FolderDisplayLocation.text(path: local, volumeName: nil, mediaType: .internalVolume)
                    == "On My iPhone › Clients › " + name)
            #expect(
                FolderDisplayLocation.text(
                    path: "/Shoots/" + name, volumeName: nil, mediaType: .unknown)
                    == "Shoots › " + name)
        }
    }

    @Test func cloudDriveHidesImplementationNames() {
        #expect(
            FolderDisplayLocation.text(
                path:
                    "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Shoots/2026",
                volumeName: nil, mediaType: .cloudProvider) == "iCloud Drive › Shoots › 2026")
    }

    @Test func externalDriveUsesDisplayVolumeWhenKnown() {
        let path =
            "/private/var/mobile/Library/LiveFiles/10000000-0000-0000-0000-000000000002/Shoots/2026"
        #expect(
            FolderDisplayLocation.text(
                path: path, volumeName: "Field Drive", mediaType: .externalDrive)
                == "Field Drive › Shoots › 2026")
        #expect(
            FolderDisplayLocation.text(path: path, volumeName: nil, mediaType: .externalDrive)
                == "Shoots › 2026")
    }

    @Test func unknownAndSingleFolderPathsStayShort() {
        #expect(
            FolderDisplayLocation.text(path: "/Shoots", volumeName: nil, mediaType: .unknown)
                == "Shoots")
        #expect(
            FolderDisplayLocation.text(
                path: "/private/var/mobile/Mystery/Shoots/2026", volumeName: nil,
                mediaType: .unknown) == "Shoots › 2026")
        #expect(
            FolderDisplayLocation.text(
                path: "/private/var/mobile", volumeName: nil, mediaType: .unknown
            ).isEmpty)
        #expect(
            FolderDisplayLocation.text(
                path: "/Provider/Shoots/2026", volumeName: "Cloud Studio", mediaType: .cloudProvider
            ) == "Cloud Studio › Shoots › 2026")
    }
}
