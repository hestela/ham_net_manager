#ifndef FLUTTER_NET_MANAGER_APPLICATION_H_
#define FLUTTER_NET_MANAGER_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(NetManagerApplication,
                     net_manager_application,
                     NET_MANAGER,
                     APPLICATION,
                     GtkApplication)

/**
 * net_manager_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #NetManagerApplication.
 */
NetManagerApplication* net_manager_application_new();

#endif  // FLUTTER_NET_MANAGER_APPLICATION_H_
