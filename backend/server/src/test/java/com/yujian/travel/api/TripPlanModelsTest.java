package com.yujian.travel.api;

import jakarta.validation.Validation;
import jakarta.validation.ValidatorFactory;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 局部修改请求的校验契约。
 *
 * APK 的重命名输入框限 40 字，服务端也必须挡住同样的上限：否则超长标题
 * 在客户端能输入、到数据库才失败（或者更糟——被写进去把列表撑爆）。
 * 这里直接验注解，不启动 Spring 上下文。
 */
class TripPlanModelsTest {

    @Test
    void rejectsATitleLongerThanTheClientLimit() {
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            var violations = factory.getValidator().validate(
                new TripPlanModels.PatchRequest("豫".repeat(41), null, null));

            assertThat(violations).hasSize(1);
            assertThat(violations.iterator().next().getMessage())
                .isEqualTo("行程名称最多 40 个字");
        }
    }

    @Test
    void acceptsATitleAtTheLimitAndAnEmptyPatch() {
        try (ValidatorFactory factory = Validation.buildDefaultValidatorFactory()) {
            var validator = factory.getValidator();

            assertThat(validator.validate(
                new TripPlanModels.PatchRequest("豫".repeat(40), null, null))).isEmpty();
            // 只改强度的局部修改不该被标题规则牵连。
            assertThat(validator.validate(
                new TripPlanModels.PatchRequest(null, null, "轻松"))).isEmpty();
        }
    }
}
