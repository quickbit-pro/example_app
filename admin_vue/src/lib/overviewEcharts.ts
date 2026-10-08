// Tree-shaken ECharts registration for the Overview page. Importing this module for its side
// effect (the view does it) is enough; echarts/core `use` is idempotent, so registering the same
// modules as lib/echarts.ts is harmless. lib/overviewCharts.ts only imports types and stays DOM-free.
import { BarChart, FunnelChart, LineChart } from 'echarts/charts';
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';

use([CanvasRenderer, LineChart, BarChart, FunnelChart, GridComponent, TooltipComponent, LegendComponent]);
