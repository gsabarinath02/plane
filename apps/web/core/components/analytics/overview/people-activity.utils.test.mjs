/**
 * Copyright (c) 2023-present Plane Software, Inc. and contributors
 * SPDX-License-Identifier: AGPL-3.0-only
 * See the LICENSE file for details.
 */

import assert from "node:assert/strict";
import test from "node:test";
import { getPeopleActivityRanking } from "./people-activity.utils.ts";

test("ranks creators by ticket count and labels an unknown creator", () => {
  const chart = {
    schema: {},
    data: [
      { key: "a", name: "Alex", count: 2 },
      { key: "b", name: "Blair", count: 5 },
      { key: "none", name: "None", count: 1 },
    ],
  };

  assert.deepEqual(getPeopleActivityRanking(chart, "created"), [
    { id: "b", name: "Blair", count: 5 },
    { id: "a", name: "Alex", count: 2 },
    { id: "none", name: "Unknown creator", count: 1 },
  ]);
  assert.equal(chart.data[0].name, "Alex");
});

test("counts currently completed tickets against their assignees", () => {
  const chart = {
    schema: { started: "started", completed: "completed" },
    data: [
      { key: "a", name: "Alex", count: 8, started: 5, completed: 3 },
      { key: "b", name: "Blair", count: 6, started: 1, completed: 5 },
      { key: "none", name: "None", count: 2, started: 2 },
    ],
  };

  assert.deepEqual(getPeopleActivityRanking(chart, "assigned"), [
    { id: "a", name: "Alex", count: 8 },
    { id: "b", name: "Blair", count: 6 },
  ]);
  assert.deepEqual(getPeopleActivityRanking(chart, "completed"), [
    { id: "b", name: "Blair", count: 5 },
    { id: "a", name: "Alex", count: 3 },
  ]);
});

test("shows no completion ranking when no tickets are completed", () => {
  assert.deepEqual(
    getPeopleActivityRanking({ schema: {}, data: [{ key: "a", name: "Alex", count: 2 }] }, "completed"),
    []
  );
  assert.deepEqual(getPeopleActivityRanking(undefined, "created"), []);
});
