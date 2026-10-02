package com.yujian.travel.service;

import com.yujian.travel.ai.PromptDefaults;
import com.yujian.travel.common.ApiException;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class PromptVersionServiceTest {
    @Test
    void fallsBackToBuiltInPromptWhenStorageIsUnavailable() {
        PromptVersionService service = new PromptVersionService(null);

        assertThat(service.currentVersion()).isEqualTo(PromptDefaults.CURRENT_VERSION);
        assertThat(service.currentSystemPrompt()).contains("豫见智旅");
        assertThat(service.list()).hasSize(1);
        assertThat(service.current().active()).isTrue();
    }

    @Test
    void createReportsStorageUnavailableInsteadOfSilentlyDroppingVersion() {
        PromptVersionService service = new PromptVersionService(null);

        assertThatThrownBy(() -> service.create("v9", "test prompt", "test"))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("没有启用提示词版本存储");
    }
}
