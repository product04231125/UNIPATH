#ifndef DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
#define DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_

#include <cstdint>
#include <map>
#include <string>

#include "flutter_plugin_registrar.h"
#include "flutter_window.h"
#include "flutter_window_wrapper.h"

class MultiWindowManager {
 public:
  static MultiWindowManager* Instance();

  MultiWindowManager();

  std::string Create(const flutter::EncodableMap* args);

  void AttachFlutterMainWindow(HWND main_window_handle,
                               FlutterDesktopPluginRegistrarRef registrar);

  FlutterWindowWrapper* GetWindow(const std::string& window_id);

  void RemoveWindow(const std::string& window_id);

  void RemoveManagedFlutterWindowLater(const std::string& window_id);

  // Called from the main event loop after a child destruction callback ends.
  void CleanupRemovedWindows();

  flutter::EncodableList GetAllWindows();

  std::vector<std::string> GetAllWindowIds();

 private:
  void NotifyWindowsChanged();

  std::map<std::string, std::unique_ptr<FlutterWindowWrapper>> windows_;
  std::map<std::string, std::unique_ptr<FlutterWindow>>
      managed_flutter_windows_;
  std::vector<std::string> pending_remove_ids_;
};

#endif  // DESKTOP_MULTI_WINDOW_WINDOWS_MULTI_WINDOW_MANAGER_H_
