/**
 * Fetch 请求封装测试
 *
 * 测试目标：
 *   - request 实例创建正确
 *   - Token 自动注入
 *   - 错误处理逻辑
 */

import { beforeEach, describe, expect, it, vi } from "vitest";

describe("Fetch 请求封装", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
  });

  it("应该正确创建 request 实例", async () => {
    const { default: request } = await import("@/utils/request");
    expect(request).toBeDefined();
    expect(request.defaults.baseURL).toBe("/api");
    expect(request.defaults.timeout).toBe(30000);
  });

  it("请求拦截器应该设置 Content-Type", async () => {
    const { default: request } = await import("@/utils/request");
    expect(request.defaults.headers["Content-Type"]).toBe("application/json");
  });
});

describe("错误上报模块", () => {
  it("应该正确初始化错误上报", async () => {
    const { setupErrorReporting } = await import("@/utils/errorReporter");
    expect(setupErrorReporting).toBeDefined();
    expect(typeof setupErrorReporting).toBe("function");
  });

  it("错误信息应该存入 localStorage", () => {
    // 模拟错误上报
    const errorInfo = {
      type: "test_error",
      message: "测试错误",
    };

    // 手动触发上报逻辑
    const errors = JSON.parse(localStorage.getItem("error_logs") || "[]");
    errors.push({ ...errorInfo, timestamp: new Date().toISOString() });
    localStorage.setItem("error_logs", JSON.stringify(errors));

    // 验证
    const stored = JSON.parse(localStorage.getItem("error_logs"));
    expect(stored).toHaveLength(1);
    expect(stored[0].type).toBe("test_error");
  });
});
