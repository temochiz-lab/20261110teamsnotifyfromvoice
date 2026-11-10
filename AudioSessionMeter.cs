using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace TeamsAudioRelay {
    public sealed class SessionPeak {
        public uint ProcessId { get; set; }
        public float Peak { get; set; }
        public string DeviceId { get; set; }
    }

    public static class AudioSessions {
        private enum DataFlow { Render, Capture, All }
        private enum Role { Console, Multimedia, Communications }
        private enum ClsContext : uint { All = 23 }

        [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
        private class EnumeratorComObject { }

        [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDeviceEnumerator {
            [PreserveSig] int EnumAudioEndpoints(DataFlow flow, uint stateMask, out IMMDeviceCollection devices);
            [PreserveSig] int GetDefaultAudioEndpoint(DataFlow flow, Role role, out IMMDevice device);
            [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
            [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
            [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
        }

        [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDeviceCollection {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int Item(uint index, out IMMDevice device);
        }

        [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IMMDevice {
            [PreserveSig] int Activate(ref Guid iid, ClsContext context, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
            [PreserveSig] int OpenPropertyStore(uint access, out IntPtr properties);
            [PreserveSig] int GetId(out IntPtr id);
            [PreserveSig] int GetState(out uint state);
        }

        [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionManager2 {
            [PreserveSig] int GetAudioSessionControl(ref Guid sessionId, uint streamFlags, out IAudioSessionControl session);
            [PreserveSig] int GetSimpleAudioVolume(ref Guid sessionId, uint streamFlags, out IntPtr volume);
            [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessions);
            [PreserveSig] int RegisterSessionNotification(IntPtr notification);
            [PreserveSig] int UnregisterSessionNotification(IntPtr notification);
            [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr notification);
            [PreserveSig] int UnregisterDuckNotification(IntPtr notification);
        }

        [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionEnumerator {
            [PreserveSig] int GetCount(out int count);
            [PreserveSig] int GetSession(int index, out IAudioSessionControl session);
        }

        [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IAudioSessionControl {
            [PreserveSig] int GetState(out int state);
            [PreserveSig] int GetDisplayName(out IntPtr name);
            [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name, ref Guid context);
            [PreserveSig] int GetIconPath(out IntPtr path);
            [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path, ref Guid context);
            [PreserveSig] int GetGroupingParam(out Guid groupingId);
            [PreserveSig] int SetGroupingParam(ref Guid groupingId, ref Guid context);
            [PreserveSig] int RegisterAudioSessionNotification(IntPtr notification);
            [PreserveSig] int UnregisterAudioSessionNotification(IntPtr notification);
        }

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetProcessIdDelegate(IntPtr self, out uint processId);

        [UnmanagedFunctionPointer(CallingConvention.StdCall)]
        private delegate int GetPeakValueDelegate(IntPtr self, out float peak);

        public static SessionPeak[] ReadDefaultRenderSessions() {
            IMMDevice device = null;
            IAudioSessionManager2 manager = null;
            IAudioSessionEnumerator sessions = null;
            object enumeratorObject = null;
            var result = new List<SessionPeak>();
            try {
                enumeratorObject = new EnumeratorComObject();
                var enumerator = (IMMDeviceEnumerator)enumeratorObject;
                Check(enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia, out device));
                Guid managerIid = typeof(IAudioSessionManager2).GUID;
                object managerObject;
                Check(device.Activate(ref managerIid, ClsContext.All, IntPtr.Zero, out managerObject));
                manager = (IAudioSessionManager2)managerObject;
                Check(manager.GetSessionEnumerator(out sessions));
                int count;
                Check(sessions.GetCount(out count));

                for (int i = 0; i < count; i++) {
                    IAudioSessionControl session = null;
                    try {
                        if (sessions.GetSession(i, out session) != 0 || session == null) continue;
                        uint processId;
                        float peak;
                        if (TryReadSession(session, out processId, out peak))
                            result.Add(new SessionPeak { ProcessId = processId, Peak = peak });
                    } catch { }
                    finally {
                        if (session != null && Marshal.IsComObject(session)) Marshal.ReleaseComObject(session);
                    }
                }
                return result.ToArray();
            }
            finally {
                if (sessions != null && Marshal.IsComObject(sessions)) Marshal.ReleaseComObject(sessions);
                if (manager != null && Marshal.IsComObject(manager)) Marshal.ReleaseComObject(manager);
                if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                if (enumeratorObject != null && Marshal.IsComObject(enumeratorObject)) Marshal.ReleaseComObject(enumeratorObject);
            }
        }

        public static SessionPeak[] ReadAllRenderSessions() {
            IMMDeviceEnumerator enumerator = null;
            object enumeratorObject = null;
            IMMDeviceCollection devices = null;
            var result = new List<SessionPeak>();
            int readableDevices = 0;
            try {
                enumeratorObject = new EnumeratorComObject();
                enumerator = (IMMDeviceEnumerator)enumeratorObject;
                Check(enumerator.EnumAudioEndpoints(DataFlow.Render, 1, out devices));
                uint count;
                Check(devices.GetCount(out count));
                for (uint i = 0; i < count; i++) {
                    IMMDevice device = null;
                    try {
                        Check(devices.Item(i, out device));
                        IntPtr idPointer = IntPtr.Zero;
                        string deviceId = null;
                        try {
                            Check(device.GetId(out idPointer));
                            deviceId = Marshal.PtrToStringUni(idPointer);
                        } finally {
                            if (idPointer != IntPtr.Zero) Marshal.FreeCoTaskMem(idPointer);
                        }
                        result.AddRange(ReadDeviceSessions(device, deviceId));
                        readableDevices++;
                    } catch (COMException) { }
                    finally {
                        if (device != null && Marshal.IsComObject(device)) Marshal.ReleaseComObject(device);
                    }
                }
                if (readableDevices == 0) throw new InvalidOperationException("No active render device could be read.");
                return result.ToArray();
            } finally {
                if (devices != null && Marshal.IsComObject(devices)) Marshal.ReleaseComObject(devices);
                if (enumerator != null && Marshal.IsComObject(enumerator)) Marshal.ReleaseComObject(enumerator);
                if (enumeratorObject != null && Marshal.IsComObject(enumeratorObject)) Marshal.ReleaseComObject(enumeratorObject);
            }
        }

        private static SessionPeak[] ReadDeviceSessions(IMMDevice device, string deviceId) {
            IAudioSessionManager2 manager = null;
            IAudioSessionEnumerator sessions = null;
            var result = new List<SessionPeak>();
            try {
                Guid managerIid = typeof(IAudioSessionManager2).GUID;
                object managerObject;
                Check(device.Activate(ref managerIid, ClsContext.All, IntPtr.Zero, out managerObject));
                manager = (IAudioSessionManager2)managerObject;
                Check(manager.GetSessionEnumerator(out sessions));
                int count;
                Check(sessions.GetCount(out count));
                for (int i = 0; i < count; i++) {
                    IAudioSessionControl session = null;
                    try {
                        if (sessions.GetSession(i, out session) != 0 || session == null) continue;
                        uint processId;
                        float peak;
                        if (TryReadSession(session, out processId, out peak))
                            result.Add(new SessionPeak { ProcessId = processId, Peak = peak, DeviceId = deviceId });
                    } catch { }
                    finally {
                        if (session != null && Marshal.IsComObject(session)) Marshal.ReleaseComObject(session);
                    }
                }
                return result.ToArray();
            } finally {
                if (sessions != null && Marshal.IsComObject(sessions)) Marshal.ReleaseComObject(sessions);
                if (manager != null && Marshal.IsComObject(manager)) Marshal.ReleaseComObject(manager);
            }
        }

        private static bool TryReadSession(IAudioSessionControl session, out uint processId, out float peak) {
            processId = 0;
            peak = 0;
            IntPtr unknown = IntPtr.Zero, control2 = IntPtr.Zero, meter = IntPtr.Zero;
            try {
                unknown = Marshal.GetIUnknownForObject(session);
                Guid control2Iid = new Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D");
                Guid meterIid = new Guid("C02216F6-8C67-4B5B-9D00-D008E73E0064");
                if (Marshal.QueryInterface(unknown, ref control2Iid, out control2) != 0) return false;
                if (Marshal.QueryInterface(unknown, ref meterIid, out meter) != 0) return false;
                var getProcessId = Marshal.GetDelegateForFunctionPointer<GetProcessIdDelegate>(GetVtableMethod(control2, 14));
                var getPeak = Marshal.GetDelegateForFunctionPointer<GetPeakValueDelegate>(GetVtableMethod(meter, 3));
                return getProcessId(control2, out processId) >= 0 && getPeak(meter, out peak) >= 0;
            }
            finally {
                if (meter != IntPtr.Zero) Marshal.Release(meter);
                if (control2 != IntPtr.Zero) Marshal.Release(control2);
                if (unknown != IntPtr.Zero) Marshal.Release(unknown);
            }
        }

        private static IntPtr GetVtableMethod(IntPtr instance, int index) {
            IntPtr vtable = Marshal.ReadIntPtr(instance);
            return Marshal.ReadIntPtr(vtable, index * IntPtr.Size);
        }

        private static void Check(int hr) {
            if (hr < 0) Marshal.ThrowExceptionForHR(hr);
        }
    }
}


