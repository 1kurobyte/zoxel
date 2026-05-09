const c = @import("c");
const std = @import("std");

pub const Window = struct {
    width: u32,
    height: u32,
    title: [*c]const u8,

    window: *c.struct_GLFWwindow,

    pub fn init(title: [*c]const u8, width: u32, height: u32) !Window {
        if (c.glfwInit() != c.GLFW_TRUE) return error.GlfwInitFailed;

        if (c.glfwVulkanSupported() != c.GLFW_TRUE) {
            std.log.err("Vulkan not supported", .{});
            return error.VulkanMissing;
        }

        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_FALSE);
        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHintString(c.GLFW_WAYLAND_APP_ID, title);

        const window = c.glfwCreateWindow(
            @intCast(width),
            @intCast(height),
            title,
            null,
            null,
        ) orelse return error.WindowInitFailed;

        var actual_width: c_int = undefined;
        var actual_height: c_int = undefined;

        // request actual dimensions from window manager
        c.glfwGetWindowSize(window, &actual_width, &actual_height);

        return .{
            .width = @intCast(actual_width),
            .height = @intCast(actual_height),
            .title = title,
            .window = window,
        };
    }

    pub fn deinit(self: *Window) void {
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
    }
};
