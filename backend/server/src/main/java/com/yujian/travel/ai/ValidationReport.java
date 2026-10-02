package com.yujian.travel.ai;

import java.util.List;

public record ValidationReport(List<String> warnings, boolean feasible, String intensityReason) {
}
