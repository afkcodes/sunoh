import { useQuery } from '@tanstack/react-query';
import { Response } from '~types/common.types';

const useFetch = ({
  queryKey,
  queryFn,
  shouldFetchOnLoad = true,
  staleTime = 50000
}: {
  queryKey: string[];
  queryFn: (param?: any) => Promise<Response>;
  shouldFetchOnLoad?: boolean;
  staleTime?: number;
}) => {
  const { isError, isLoading, isFetched, refetch, data, isSuccess, isPending, status } = useQuery({
    queryKey,
    queryFn,
    enabled: shouldFetchOnLoad,
    staleTime
  });

  return {
    isError,
    isLoading,
    isFetched,
    refetch,
    data,
    isSuccess,
    isPending,
    status
  };
};

export default useFetch;
