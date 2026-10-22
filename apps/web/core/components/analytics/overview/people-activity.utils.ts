/**
 * Copyright (c) 2023-present Plane Software, Inc. and contributors
 * SPDX-License-Identifier: AGPL-3.0-only
 * See the LICENSE file for details.
 */

import type { TChart } from "@plane/types";

export type TPeopleActivityMetric = "created" | "assigned" | "completed";

export type TPersonCount = {
  id: string;
  name: string;
  count: number;
};

export const PEOPLE_RANKING_PREVIEW_SIZE = 5;

export const getVisiblePeopleActivityRanking = (entries: TPersonCount[], showAll: boolean): TPersonCount[] =>
  showAll ? entries : entries.slice(0, PEOPLE_RANKING_PREVIEW_SIZE);

export const getPeopleActivityRanking = (chart: TChart | undefined, metric: TPeopleActivityMetric): TPersonCount[] => {
  if (!chart) return [];

  const completedKey =
    metric === "completed" ? Object.keys(chart.schema).find((key) => key.toLowerCase() === "completed") : undefined;

  if (metric === "completed" && !completedKey) return [];

  return (
    chart.data
      .map((item) => {
        const count = metric === "completed" ? item[completedKey ?? ""] : item.count;
        const name = item.name?.trim();
        const isUnassigned = !item.key || ["none", "null"].includes(String(item.key).toLowerCase());

        return {
          id: String(item.key),
          name: name && name.toLowerCase() !== "none" ? name : metric === "created" ? "Unknown creator" : "Unassigned",
          count: metric !== "created" && isUnassigned ? 0 : Number.isFinite(count) ? count : 0,
        };
      })
      .filter((item) => item.count > 0)
      // The mapped array is new, so sorting cannot change the chart response.
      // eslint-disable-next-line unicorn/no-array-sort
      .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name))
  );
};
