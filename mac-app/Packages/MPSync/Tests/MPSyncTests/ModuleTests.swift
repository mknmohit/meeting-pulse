import Testing

@testable import MPSync

@Test
func syncModuleLoads() {
  #expect(MPSyncModule.name == "MPCore sync")
  #expect(MPSyncModule.clientProduct == "Supabase")
}
