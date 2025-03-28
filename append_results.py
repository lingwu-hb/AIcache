#!/usr/bin/env python3
import pandas as pd
import sys
import os
# python3 append_results.py new_data.xlsx

def append_columns(new_xlsx, result_xlsx='result.xlsx'):
    """
    根据第一列作为key，将新数据的列追加到已有的Excel文件中
    :param new_xlsx: 新的xlsx文件路径
    :param result_xlsx: 目标xlsx文件路径
    """
    try:
        # 读取新的测试结果
        new_df = pd.read_excel(new_xlsx)
        
        # 获取第一列的名称（作为key列）
        key_column = new_df.columns[0]
        
        # 获取要追加的新列名（除了第一列外的所有列）
        new_columns = new_df.columns[1:].tolist()
        
        # 读取现有的结果文件或创建新文件
        if os.path.exists(result_xlsx):
            result_df = pd.read_excel(result_xlsx)
            
            # 检查是否有重复的列名
            duplicate_columns = set(new_columns) & set(result_df.columns)
            if duplicate_columns:
                print(f"Warning: Found duplicate columns: {duplicate_columns}")
                print("These columns will be updated with new values")
            
            # 保存原始的key列顺序
            original_keys = result_df[key_column].tolist()
            
            # 重命名新数据中的key列，以避免合并时的冲突
            new_df_renamed = new_df.copy()
            new_df_renamed = new_df_renamed.rename(columns={key_column: '_temp_key'})
            result_df = result_df.rename(columns={key_column: '_temp_key'})
            
            # 合并数据，保持原有行的顺序
            result_df = result_df.merge(new_df_renamed, on='_temp_key', how='left')
            
            # 添加新的行（如果有）
            new_rows = new_df_renamed[~new_df_renamed['_temp_key'].isin(original_keys)]
            if not new_rows.empty:
                result_df = pd.concat([result_df, new_rows], ignore_index=True)
            
            # 恢复原有顺序
            # 创建位置映射
            position_map = {k: i for i, k in enumerate(original_keys)}
            max_pos = len(original_keys)
            
            # 为新key分配位置
            result_df['_sort_key'] = result_df['_temp_key'].apply(
                lambda x: position_map.get(x, max_pos + len(position_map))
            )
            
            # 排序并删除临时列
            result_df = result_df.sort_values('_sort_key').drop('_sort_key', axis=1)
            
            # 恢复key列名
            result_df = result_df.rename(columns={'_temp_key': key_column})
            
        else:
            # 如果文件不存在，直接使用新数据
            result_df = new_df

        # 保存结果
        result_df.to_excel(result_xlsx, index=False)
        print(f"Results appended to {result_xlsx}")
        print(f"Key column: {key_column}")
        print(f"Added/Updated columns: {', '.join(new_columns)}")
        
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
    
    append_columns(new_xlsx) 