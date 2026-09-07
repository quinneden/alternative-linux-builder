import Foundation
import Virtualization

var buildJSON: String?
var cores: Int = 1
var memoryMiB: UInt64 = defaultMemoryMiB()
var rosetta: Bool = false

var args = Array(CommandLine.arguments.dropFirst())

while !args.isEmpty {
  let arg = args.removeFirst()
  switch arg {
  case "-h", "--help":
    printUsageAndExit()
  case "-c", "--cores":
    if let raw = args.first, let val = Int(raw) {
      cores = val
      args.removeFirst()
    }
  case "-m", "--memory":
    if let raw = args.first, let val = UInt64(raw) {
      memoryMiB = val
      args.removeFirst()
    }
  case "--rosetta":
    rosetta = true
  default:
    if buildJSON == nil {
      buildJSON = arg
    } else {
      print("unknown argument: \(arg)")
      exit(1)
    }
  }
}

guard let buildJSON else {
  print("error: path to builder JSON was not provided")
  exit(1)
}
let buildJSONURL = URL(fileURLWithPath: buildJSON, isDirectory: false)

guard let exeURL = Bundle.main.executableURL else {
  print("Unable to determine executable path.")
  exit(1)
}
let shareDirURL = exeURL.deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("share")

let initrdURL = shareDirURL.appendingPathComponent("initrd/initrd").resolvingSymlinksInPath()
let kernelURL = shareDirURL.appendingPathComponent("kernel/Image").resolvingSymlinksInPath()

let vmConfig = VZVirtualMachineConfiguration()

vmConfig.bootLoader = createBootLoader(kernelURL: kernelURL, initrdURL: initrdURL)
vmConfig.cpuCount = cores
vmConfig.memorySize = memoryMiB * 1024 * 1024
vmConfig.networkDevices = [createNetworkConfiguration()]
vmConfig.serialPorts = [createConsoleConfiguration()]

let buildRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let nixStoreURL = URL(fileURLWithPath: "/nix/store", isDirectory: true)
let buildRootShare = createDirectoryShareDevice(url: buildRootURL, tag: "build-root")
let nixStoreShare = createDirectoryShareDevice(url: nixStoreURL, tag: "nix-store")

vmConfig.directorySharingDevices = [buildRootShare, nixStoreShare]

if rosetta {
  let rosettaShare = createRosettaDirectoryShareDevice()
  vmConfig.directorySharingDevices += [rosettaShare]
}

do { try vmConfig.validate() } catch {
  print("Failed to validate the virtual machine configuration: \(error)")
  exit(EXIT_FAILURE)
}

let builderJSONURL = buildRootURL.appendingPathComponent("builder.json")
try FileManager.default.copyItem(at: buildJSONURL, to: builderJSONURL)

let virtualMachine = VZVirtualMachine(configuration: vmConfig)

let delegate = Delegate()
virtualMachine.delegate = delegate

virtualMachine.start { (result) in
  if case .failure(let error) = result {
    print("Failed to start the virtual machine. \(error)")
    exit(EXIT_FAILURE)
  }
}

RunLoop.main.run(until: Date.distantFuture)

class Delegate: NSObject {}

extension Delegate: VZVirtualMachineDelegate {
  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    exit(EXIT_SUCCESS)
  }
}

func createBootLoader(kernelURL: URL, initrdURL: URL) -> VZBootLoader {
  let bootLoader = VZLinuxBootLoader(kernelURL: kernelURL)
  bootLoader.initialRamdiskURL = initrdURL

  let kernelCommandLineArguments = [
    "console=hvc0",
    "init=/init",
    "loglevel=4",
    "panic=1",
  ]

  bootLoader.commandLine = kernelCommandLineArguments.joined(separator: " ")

  return bootLoader
}

func createConsoleConfiguration() -> VZSerialPortConfiguration {
  let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()
  let stdioAttachment = VZFileHandleSerialPortAttachment(
    fileHandleForReading: nil,
    fileHandleForWriting: FileHandle.standardOutput)

  consoleConfiguration.attachment = stdioAttachment

  return consoleConfiguration
}

func createDirectoryShareDevice(url: URL, tag: String, readOnly: Bool = false)
  -> VZVirtioFileSystemDeviceConfiguration
{
  let sharedDirectory = VZSharedDirectory(url: url, readOnly: readOnly)
  let share = VZSingleDirectoryShare(directory: sharedDirectory)
  let deviceConfig = VZVirtioFileSystemDeviceConfiguration(tag: tag)

  deviceConfig.share = share

  return deviceConfig
}

func createNetworkConfiguration() -> VZNetworkDeviceConfiguration {
  let networkConfiguration = VZVirtioNetworkDeviceConfiguration()

  networkConfiguration.attachment = VZNATNetworkDeviceAttachment()
  networkConfiguration.macAddress = VZMACAddress.randomLocallyAdministered()

  return networkConfiguration
}

func createRosettaDirectoryShareDevice() -> VZVirtioFileSystemDeviceConfiguration {
  do {
    let rosettaDirectoryShare = try VZLinuxRosettaDirectoryShare()
    let rosettaDeviceConfig = VZVirtioFileSystemDeviceConfiguration(tag: "rosetta")
    rosettaDeviceConfig.share = rosettaDirectoryShare

    return rosettaDeviceConfig
  } catch {
    print("Failed to create Rosetta directory share")
    exit(EXIT_FAILURE)
  }
}

func defaultMemoryMiB() -> UInt64 {
  let physicalMemoryMiB = ProcessInfo.processInfo.physicalMemory / 1024 / 1024
  let quarter = physicalMemoryMiB / 4

  let maxMiB = VZVirtualMachineConfiguration.maximumAllowedMemorySize / 1024 / 1024
  let minMiB = VZVirtualMachineConfiguration.minimumAllowedMemorySize / 1024 / 1024

  return min(max(quarter, minMiB), maxMiB)
}

func printUsageAndExit() -> Never {
  let message = """
    Usage: \(CommandLine.arguments[0]) [options] <path-to-build-json>

    Options:
        -c, --cores       Number of CPU cores allocated to the VM
        -m, --memory      Amount of memory allocated to the VM in mebibytes
    """

  print(message)
  exit(EX_USAGE)
}
