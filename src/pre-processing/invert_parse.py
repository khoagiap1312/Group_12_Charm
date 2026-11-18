import pandas as pd


def decode_spmf_to_file(spmf_txt_path, map_csv_path, output_txt_path):
  """Đọc file kết quả SPMF ('1 4 12 #SUP: 500'), đổi số thành tên item

  và ghi ra file .txt mới: 'RATE_SINGLE GET_FILTER_200 UA_MOBILE #SUP: 500'
  """
  # 1. Load file mapping thành dict: {'1': 'RATE_SINGLE', '2': 'UA_KNOWN_BOT', ...}
  df_map = pd.read_csv(map_csv_path, dtype=str)
  id_to_item = dict(zip(df_map.iloc[:, 0], df_map.iloc[:, 1]))

  # 2. Đọc từng dòng file SPMF, thay ID bằng tên gốc và ghi ra file mới
  with (
      open(spmf_txt_path, 'r', encoding='utf-8') as f_in,
      open(output_txt_path, 'w', encoding='utf-8') as f_out,
  ):
    for line in f_in:
      line = line.strip()
      if not line:
        continue

      if '#SUP:' in line:
        items_part, sup_part = line.split('#SUP:')
        # Ánh xạ từng ID sang tên item (nếu không có trong map thì giữ nguyên ID)
        decoded_items = [
            id_to_item.get(i, i) for i in items_part.strip().split()
        ]
        f_out.write(f"{' '.join(decoded_items)} #SUP: {sup_part.strip()}\n")
      else:
        # Trường hợp dùng hàm này để dịch ngược lại file transaction.txt (không có #SUP:)
        decoded_items = [id_to_item.get(i, i) for i in line.split()]
        f_out.write(f"{' '.join(decoded_items)}\n")


def decode_spmf_to_df(spmf_txt_path, map_csv_path):
  """Đọc file kết quả SPMF và trả về Pandas DataFrame gồm: [Items, Length, Support]"""
  df_map = pd.read_csv(map_csv_path, dtype=str)
  id_to_item = dict(zip(df_map.iloc[:, 0], df_map.iloc[:, 1]))

  rows = []
  with open(spmf_txt_path, 'r', encoding='utf-8') as f:
    for line in f:
      line = line.strip()
      if not line or '#SUP:' not in line:
        continue

      items_part, sup_part = line.split('#SUP:')
      decoded_items = [id_to_item.get(i, i) for i in items_part.strip().split()]
      support = int(sup_part.strip())

      rows.append({
          'Itemset': decoded_items,  # Dạng list các item
          'Itemset_Str': ', '.join(decoded_items),  # Dạng chuỗi để dễ đọc
          'Length': len(decoded_items),
          'Support': support,
      })

  return pd.DataFrame(rows)