/**
 * Copyright (c) 2023-present Plane Software, Inc. and contributors
 * SPDX-License-Identifier: AGPL-3.0-only
 * See the LICENSE file for details.
 */

import { observer } from "mobx-react";
import { useParams } from "next/navigation";
import useSWR from "swr";
import type { TChart } from "@plane/types";
import { ChartXAxisProperty } from "@plane/types";
import { useAnalytics } from "@/hooks/store/use-analytics";
import { AnalyticsService } from "@/services/analytics.service";
import AnalyticsSectionWrapper from "../analytics-section-wrapper";
import { getPeopleActivityRanking } from "./people-activity.utils";
import type { TPersonCount } from "./people-activity.utils";

const analyticsService = new AnalyticsService();

type TPeopleRankingProps = {
  title: string;
  description: string;
  emptyMessage: string;
  color: string;
  entries: TPersonCount[];
  isLoading: boolean;
  hasError: boolean;
};

function PeopleRanking({ title, description, emptyMessage, color, entries, isLoading, hasError }: TPeopleRankingProps) {
  const total = entries.reduce((sum, entry) => sum + entry.count, 0);
  const topCount = entries[0]?.count ?? 0;

  return (
    <div className="min-w-0 border-t border-subtle pt-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-14 font-semibold text-primary">{title}</h3>
          <p className="mt-1 text-12 text-tertiary">{description}</p>
        </div>
        {!isLoading && !hasError && <span className="text-20 font-semibold text-primary tabular-nums">{total}</span>}
      </div>

      {isLoading ? (
        <div className="mt-6 space-y-5" aria-label={`Loading ${title.toLowerCase()}`}>
          {[0, 1, 2, 3].map((item) => (
            <div key={item} className="h-7 animate-pulse rounded bg-layer-1" />
          ))}
        </div>
      ) : hasError ? (
        <p className="mt-6 text-13 text-tertiary">Could not load these stats. Refresh to try again.</p>
      ) : entries.length === 0 ? (
        <p className="mt-6 text-13 text-tertiary">{emptyMessage}</p>
      ) : (
        <ol className="mt-6 space-y-4">
          {entries.slice(0, 5).map((entry, index) => (
            <li key={entry.id} className="min-w-0">
              <div className="mb-1.5 flex items-center justify-between gap-3 text-13">
                <div className="flex min-w-0 items-center gap-2">
                  <span className="w-4 shrink-0 text-12 text-tertiary tabular-nums">{index + 1}</span>
                  <span className="truncate text-primary" title={entry.name}>
                    {entry.name}
                  </span>
                </div>
                <span className="shrink-0 font-medium text-primary tabular-nums">{entry.count}</span>
              </div>
              <div className="ml-6 h-1.5 overflow-hidden rounded-full bg-layer-1" aria-hidden="true">
                <div
                  className="h-full rounded-full"
                  style={{ width: `${(entry.count / topCount) * 100}%`, backgroundColor: color }}
                />
              </div>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

const PeopleActivity = observer(function PeopleActivity() {
  const { workspaceSlug } = useParams();
  const { selectedProjects, selectedCycle, selectedModule, isPeekView, isEpic } = useAnalytics();
  const slug = workspaceSlug.toString();
  const selectedProjectIds = selectedProjects.join(",");
  const filterKey = `${slug}-${selectedProjectIds}-${selectedCycle}-${selectedModule}-${isPeekView}-${isEpic}`;
  const filters = {
    ...(selectedProjectIds ? { project_ids: selectedProjectIds } : {}),
    ...(selectedCycle ? { cycle_id: selectedCycle } : {}),
    ...(selectedModule ? { module_id: selectedModule } : {}),
    ...(isEpic ? { epic: true } : {}),
  };

  const {
    data: creators,
    isLoading: creatorsLoading,
    error: creatorsError,
  } = useSWR(`people-activity-creators-${filterKey}`, () =>
    analyticsService.getAdvanceAnalyticsCharts<TChart>(
      slug,
      "custom-work-items",
      { ...filters, x_axis: ChartXAxisProperty.CREATED_BY },
      isPeekView
    )
  );
  const {
    data: assignees,
    isLoading: assigneesLoading,
    error: assigneesError,
  } = useSWR(`people-activity-assignees-${filterKey}`, () =>
    analyticsService.getAdvanceAnalyticsCharts<TChart>(
      slug,
      "custom-work-items",
      { ...filters, x_axis: ChartXAxisProperty.ASSIGNEES, group_by: ChartXAxisProperty.STATE_GROUPS },
      isPeekView
    )
  );

  return (
    <AnalyticsSectionWrapper title="Work items by person">
      <p className="mb-6 text-13 text-tertiary">
        All-time counts for the selected projects. Completed work items are credited to their current assignees.
      </p>
      <div className="grid grid-cols-1 gap-8 lg:grid-cols-3">
        <PeopleRanking
          title="Created by"
          description="Who opened the most work items"
          emptyMessage="No work items have been created yet."
          color="#1192E8"
          entries={getPeopleActivityRanking(creators, "created")}
          isLoading={creatorsLoading}
          hasError={Boolean(creatorsError)}
        />
        <PeopleRanking
          title="Assigned to"
          description="Current work item assignments"
          emptyMessage="No work items are assigned yet."
          color="#8A63D2"
          entries={getPeopleActivityRanking(assignees, "assigned")}
          isLoading={assigneesLoading}
          hasError={Boolean(assigneesError)}
        />
        <PeopleRanking
          title="Completed"
          description="Completed work items by current assignee"
          emptyMessage="No assigned work items are completed yet."
          color="#198038"
          entries={getPeopleActivityRanking(assignees, "completed")}
          isLoading={assigneesLoading}
          hasError={Boolean(assigneesError)}
        />
      </div>
      <p className="mt-5 text-12 text-tertiary">
        Unassigned work items are excluded from the assignee rankings. Work items with multiple assignees count once for
        each person.
      </p>
    </AnalyticsSectionWrapper>
  );
});

export default PeopleActivity;
