#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import pandas as pd
from pathlib import Path

def csv_to_excel(csv_file):
    # 读取CSV文件
    df = pd.read_csv(csv_file)
    
    # 创建同名的xlsx文件
    excel_file = csv_file.replace('.csv', '.xlsx')
    
    # 创建一个Excel writer对象
    writer = pd.ExcelWriter(excel_file, engine='xlsxwriter')
    
    # 将数据写入Excel
    df.to_excel(writer, index=False, sheet_name='Results')
    
    # 获取workbook和worksheet对象
    workbook = writer.book
    worksheet = writer.sheets['Results']
    
    # 设置列宽
    for i, col in enumerate(df.columns):
        max_length = max(
            df[col].astype(str).apply(len).max(),  # 列中最长的内容
            len(str(col))  # 列名长度
        )
        worksheet.set_column(i, i, max_length + 2)  # 设置列宽（加2为了有一些边距）
    
    # 添加百分比格式
    percent_format = workbook.add_format({'num_format': '0.00%'})
    for col in ['IOPS(%)', 'BW(%)']:
        if col in df.columns:
            col_idx = df.columns.get_loc(col)
            worksheet.set_column(col_idx, col_idx, None, percent_format)
            # 将百分比值从字符串转换为小数
            for row in range(len(df)):
                try:
                    val = df.iloc[row][col]
                    if isinstance(val, str) and val.strip():
                        worksheet.write(row + 1, col_idx, float(val.strip()) / 100)
                except:
                    pass
    
    # 保存文件
    writer.close()
    return excel_file

if __name__ == '__main__':
    # 获取当前目录下所有的csv文件
    csv_files = Path('.').glob('*.csv')
    
    for csv_file in csv_files:
        # 检查是否已经有对应的xlsx文件
        xlsx_file = csv_file.with_suffix('.xlsx')
        if xlsx_file.exists():
            continue
            
        try:
            excel_file = csv_to_excel(str(csv_file))
            print(f"Successfully converted to: {excel_file}")
        except Exception as e:
            print(f"Error converting {csv_file}: {e}")
            continue