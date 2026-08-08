import Auth
import MPCore
import MPSupport
import PostgREST

public enum MPSyncModule {
  public static let name = "\(MPCoreModule.name) sync"
  public static let support = MPSupportModule.name
  public static let clientProduct = "Auth+PostgREST"
}
