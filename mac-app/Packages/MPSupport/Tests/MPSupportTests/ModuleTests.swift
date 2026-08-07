import Testing

@testable import MPSupport

@Test
func supportModuleLoads() {
  #expect(MPSupportModule.name == "MPCore support")
}
