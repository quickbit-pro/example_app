// Tree-shaken ECharts registration, done once for every admin chart. Import this module for its
// side effect before rendering a <v-chart>; lib/chartConfig.ts only imports types so it stays DOM-free.
import { BarChart, FunnelChart, LineChart, PieChart } from 'echarts/charts';
import { GridComponent, LegendComponent, TooltipComponent } from 'echarts/components';
import { use } from 'echarts/core';
import { CanvasRenderer } from 'echarts/renderers';

use([CanvasRenderer, BarChart, LineChart, PieChart, FunnelChart, GridComponent, TooltipComponent, LegendComponent]);
