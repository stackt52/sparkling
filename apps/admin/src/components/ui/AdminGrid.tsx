'use client';
import { DataGrid, type DataGridProps, type GridValidRowModel } from '@mui/x-data-grid';
import { fonts, tk } from '@/theme/tokens';

/** DataGrid styled to the admin table spec (overline headers, tonal hover, no outer border). */
export default function AdminGrid<R extends GridValidRowModel>({ sx, ...props }: DataGridProps<R>) {
  return (
    <DataGrid<R>
      disableColumnMenu
      disableRowSelectionOnClick
      hideFooter={props.hideFooter ?? true}
      rowHeight={60}
      columnHeaderHeight={48}
      autoHeight
      sx={{
        border: 'none',
        fontFamily: fonts.sans,
        fontSize: 14.5,
        color: tk.onSurface,
        '--DataGrid-rowBorderColor': tk.outlineVariant,
        '& .MuiDataGrid-columnHeaders, & .MuiDataGrid-columnHeader': { bgcolor: 'transparent', color: tk.onSurfaceVariant },
        '& .MuiDataGrid-columnHeaderTitle': { fontWeight: 600, fontSize: 11.5, letterSpacing: '0.06em', textTransform: 'uppercase' },
        '& .MuiDataGrid-columnSeparator': { display: 'none' },
        '& .MuiDataGrid-cell': { display: 'flex', alignItems: 'center', outline: 'none !important', borderTop: `1px solid ${tk.outlineVariant}` },
        '& .MuiDataGrid-cell:focus-visible': { outline: `3px solid ${tk.primary} !important`, outlineOffset: -3 },
        '& .MuiDataGrid-row:hover': { bgcolor: tk.surfaceContainer },
        '& .MuiDataGrid-row.row-clickable': { cursor: 'pointer' },
        '& .MuiDataGrid-row.row-error': { bgcolor: `color-mix(in srgb, ${tk.errorContainer} 45%, transparent)` },
        '& .MuiDataGrid-row.row-warning': { bgcolor: `color-mix(in srgb, ${tk.warningContainer} 45%, transparent)` },
        '& .MuiDataGrid-row.row-error:hover': { bgcolor: `color-mix(in srgb, ${tk.errorContainer} 70%, transparent)` },
        '& .MuiDataGrid-row.row-warning:hover': { bgcolor: `color-mix(in srgb, ${tk.warningContainer} 70%, transparent)` },
        '& .MuiDataGrid-footerContainer': { borderTop: `1px solid ${tk.outlineVariant}` },
        '& .MuiDataGrid-overlay': { bgcolor: 'transparent' },
        '& .MuiDataGrid-filler': { display: 'none' },
        '& .mono': { fontFamily: fonts.mono },
        ...sx,
      }}
      {...props}
    />
  );
}
