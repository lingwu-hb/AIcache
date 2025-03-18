#!/usr/bin/env python3
import pandas as pd
import sys
import os
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

def append_results(new_xlsx, result_xlsx='result.xlsx'):
    """
    将新的测试结果追加到汇总Excel文件中
    :param new_xlsx: 新生成的xlsx文件路径（包含单次测试结果）
    :param result_xlsx: 汇总结果的xlsx文件路径
    """
    try:
        # 读取新的测试结果
        new_df = pd.read_excel(new_xlsx)
        
        # 从新数据中获取算法名称
        algorithm = new_df['Algorithm'].iloc[0]
        if pd.isna(algorithm) or algorithm == 'unknown':
            # 尝试从文件路径中提取算法名称
            dir_name = os.path.dirname(new_xlsx)
            last_dir = os.path.basename(dir_name)
            if '+' in last_dir:
                algorithm = last_dir.split('+')[0]
            else:
                print("Warning: Could not determine algorithm name")
                algorithm = "Unknown"

        print(f"Processing results for algorithm: {algorithm}")

        # 提取需要的列并按Trace排序
        new_data = new_df[['Trace', 'KIOPS', 'BW(MiB/s)']].sort_values('Trace')
        
        # 重命名列，添加算法标识
        new_data = new_data.rename(columns={
            'KIOPS': f'KIOPS_{algorithm}',
            'BW(MiB/s)': f'BW_{algorithm}'
        })

        # 读取现有的结果文件
        if os.path.exists(result_xlsx):
            result_df = pd.read_excel(result_xlsx)
            # 保存原始的Trace列及其顺序
            original_df = result_df.copy()
            
            # 基于Trace列合并数据
            # how='left' 确保只保留原始文件中的行，并按原始顺序
            result_df = result_df.merge(new_data, on='Trace', how='left')
            
            # 对于新数据中存在但原始数据中不存在的Trace，添加新行
            new_traces = new_data[~new_data['Trace'].isin(result_df['Trace'])]
            if not new_traces.empty:
                result_df = pd.concat([result_df, new_traces], ignore_index=True)
            
            # 使用原始DataFrame的索引重新排序
            # 创建一个映射字典，保存每个Trace值在原始DataFrame中的位置
            original_positions = {trace: idx for idx, trace in enumerate(original_df['Trace'])}
            
            # 为新的Trace赋予较大的位置值，确保它们排在最后
            max_pos = len(original_positions)
            for trace in result_df['Trace']:
                if trace not in original_positions:
                    original_positions[trace] = max_pos
                    max_pos += 1
            
            # 使用这个位置信息排序
            result_df['_original_position'] = result_df['Trace'].map(original_positions)
            result_df = result_df.sort_values('_original_position').drop('_original_position', axis=1)
        else:
            # 如果文件不存在，使用新数据创建
            result_df = new_data
            # 新文件才需要排序
            result_df = result_df.sort_values('Trace', ascending=True)

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
    # 获取当前目录
    current_dir = os.path.dirname(os.path.abspath(__file__))
    default_csv_dir = os.path.join(current_dir, "csv")
    
    # 获取最新的xlsx文件
    if len(sys.argv) > 1:
        new_xlsx = sys.argv[1]
    else:
        # 查找最新的xlsx文件
        xlsx_files = [f for f in os.listdir(default_csv_dir) if f.endswith('.xlsx') and f.startswith('result_')]
        if not xlsx_files:
            print(f"Error: No result_*.xlsx files found in {default_csv_dir}")
            sys.exit(1)
        latest_file = max(xlsx_files, key=lambda x: os.path.getctime(os.path.join(default_csv_dir, x)))
        new_xlsx = os.path.join(default_csv_dir, latest_file)
    
    if not os.path.exists(new_xlsx):
        print(f"Error: File {new_xlsx} not found")
        sys.exit(1)
    
    print(f"Processing file: {new_xlsx}")
    append_results(new_xlsx) 