import Foundation
import Virtualization

var initrdPath: String?
var kernelPath: String?
var builderJSONPath: String?
var cores: Int = 2
var memoryMiB: UInt64 = 4096

var args = Array(CommandLine.arguments.dropFirst())

while !args.isEmpty {
  let arg = args.removeFirst()
  switch arg {
  case "-c", "-cores":
    if let raw = args.first, let val = Int(raw) {
      cores = val
      args.removeFirst()
    }
  case "-m", "--memory":
    if let raw = args.first, let val = UInt64(raw) {
      memoryMiB = val
      args.removeFirst()
    }
  default:
    if kernelPath == nil {
      kernelPath = arg
    } else if initrdPath == nil {
      initrdPath = arg
    } else if builderJSONPath == nil {
      builderJSONPath = arg
    } else {
      print("Unknown argument: \(arg)")
      exit(1)
    }
  }
}

guard let kernel = kernelPath, let initrd = initrdPath, let builderJSON = builderJSONPath else {
  printUsageAndExit()
}

let kernelURL = URL(fileURLWithPath: kernel, isDirectory: false)
let initrdURL = URL(fileURLWithPath: initrd, isDirectory: false)
let builderJSONURL = URL(fileURLWithPath: builderJSON, isDirectory: false)

let configuration = VZVirtualMachineConfiguration()
configuration.cpuCount = cores
configuration.memorySize = memoryMiB * 1024 * 1024
configuration.serialPorts = [createConsoleConfiguration()]
configuration.networkDevices = [createNetworkConfiguration()]
configuration.bootLoader = createBootLoader(kernelURL: kernelURL, initrdURL: initrdURL)

let buildRootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let nixStoreURL = URL(fileURLWithPath: "/nix/store", isDirectory: true)
let buildRootShare = createDirectoryShareDevice(url: buildRootURL, tag: "buildroot")
let nixStoreShare = createDirectoryShareDevice(url: nixStoreURL, tag: "nix-store")
configuration.directorySharingDevices = [buildRootShare, nixStoreShare]

do { try configuration.validate() } catch {
  print("Failed to validate the virtual machine configuration. \(error)")
  exit(EXIT_FAILURE)
}

let builderJSONDestURL = buildRootURL.appendingPathComponent("builder.json")
try FileManager.default.copyItem(at: builderJSONURL, to: builderJSONDestURL)

let virtualMachine = VZVirtualMachine(configuration: configuration)

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
    print("The guest shut down. Exiting.")
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

  let inputFileHandle = FileHandle.standardInput
  let outputFileHandle = FileHandle.standardOutput

  // Put stdin into raw mode, disabling local echo, input canonicalization,
  // and CR-NL mapping.
  var attributes = termios()
  tcgetattr(inputFileHandle.fileDescriptor, &attributes)
  attributes.c_iflag &= ~tcflag_t(ICRNL)
  attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
  tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

  let stdioAttachment = VZFileHandleSerialPortAttachment(
    fileHandleForReading: inputFileHandle,
    fileHandleForWriting: outputFileHandle)

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

func printUsageAndExit() -> Never {
  let message = """
    Usage: \(CommandLine.arguments[0]) [options] <path-to-kernel> <path-to-initrd>

    Options:
        -c, --cores       Number of CPU cores allocated to the VM
        -m, --memory      Amount of memory allocated to the VM in mebibytes
    """

  print(message)
  exit(EX_USAGE)
}
