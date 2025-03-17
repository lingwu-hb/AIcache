#!/usr/bin/env python3
import pandas as pd
import sys
import os
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

def append_results(new_xlsx, result_xlsx='result.xlsx'):
    """
    将新的测试结果追加到汇总Excel文件中
    :param new_xlsx: 新生成的xlsx文件路径
    :param result_xlsx: 汇总结果的xlsx文件路径
    """
    # 读取新的测试结果
    new_df = pd.read_excel(new_xlsx)
    
    # 从文件名中提取算法名称（假设文件名格式为 .../result_2024-03-18_10-30-00.xlsx）
    algorithm = None
    with pd.ExcelFile(new_xlsx) as xls:
        if 'Results' in xls.sheet_names:
            temp_df = pd.read_excel(xls, 'Results')
            if not temp_df.empty:
                algorithm = temp_df['Algorithm'].iloc[0]
    
    if algorithm is None:
        print("Warning: Could not determine algorithm name")
        algorithm = "Unknown"

    # 提取需要的列
    new_data = new_df[['Trace', 'KIOPS', 'BW(MiB/s)']]
    
    # 重命名列，添加算法标识
    new_data = new_data.rename(columns={
        'KIOPS': f'KIOPS_{algorithm}',
        'BW(MiB/s)': f'BW_{algorithm}'
    })

    try:
        # 尝试读取现有的结果文件
        if os.path.exists(result_xlsx):
            result_df = pd.read_excel(result_xlsx)
            # 基于Trace列合并数据
            result_df = result_df.merge(new_data, on='Trace', how='outer')
        else:
            # 如果文件不存在，使用新数据创建
            result_df = new_data

        # 保存到Excel
        with pd.ExcelWriter(result_xlsx, engine='openpyxl') as writer:
            result_df.to_excel(writer, index=False, sheet_name='Results')
            
            # 获取工作表
            worksheet = writer.sheets['Results']
            
            # 定义样式
            header_fill = PatternFill(start_color='366092', end_color='366092', fill_type='solid')
            header_font = Font(color='FFFFFF', bold=True)
            centered = Alignment(horizontal='center', vertical='center')
            border = Border(
                left=Side(style='thin'),
                right=Side(style='thin'),
                top=Side(style='thin'),
                bottom=Side(style='thin')
            )
            
            # 应用表头样式
            for cell in worksheet[1]:
                cell.fill = header_fill
                cell.font = header_font
                cell.alignment = centered
                cell.border = border
            
            # 设置列宽和应用样式到所有单元格
            for idx, col in enumerate(result_df.columns):
                column = get_column_letter(idx + 1)
                max_length = max(
                    result_df[col].astype(str).apply(len).max(),
                    len(str(col))
                )
                worksheet.column_dimensions[column].width = max_length + 2
                
                # 应用样式到数据单元格
                for row in range(2, worksheet.max_row + 1):
                    cell = worksheet[f"{column}{row}"]
                    cell.alignment = centered
                    cell.border = border
                    
                    # 为数值列设置数字格式
                    if 'KIOPS' in col or 'BW' in col:
                        cell.number_format = '#,##0.00'
            
            # 冻结首行
            worksheet.freeze_panes = 'A2'

        print(f"Results appended to {result_xlsx}")
        print(f"Added columns: KIOPS_{algorithm}, BW_{algorithm}")
        
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 append_results.py <new_xlsx_file>")
        sys.exit(1)
    
    new_xlsx = sys.argv[1]
    if not os.path.exists(new_xlsx):
        print(f"Error: File {new_xlsx} not found")
        sys.exit(1)
        
    append_results(new_xlsx) 