import Testing

@testable import MPCore

@Test
func coreModuleLoads() {
  #expect(MPCoreModule.name == "MPCore")
}
